import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks a call of a function by name: which function it reaches, and its arguments against that function's
/// parameters.
struct CallChecker {
    /// A function that a call reaches, and the call's arguments, checked against its parameters.
    private typealias Match = (signature: Signature, arguments: [CheckedExpr])

    /// An argument's label and the type of its value, which choose among overloads.
    private typealias TypedArgument = (label: String?, type: RayoType)

    let expressions: ExpressionChecker

    private var errors: ErrorList { expressions.file.errors }

    /// Checks `name(arguments)`. Every argument is checked, whether or not the call matches a function.
    func call(_ name: String, at nameRange: SourceRange, _ arguments: [Argument],
              in range: SourceRange) -> CheckedExpr? {
        let candidates = functions(named: name, at: nameRange)
        // A call that reaches no function, or whose arguments fit none, was reported.
        guard let match = match(arguments, among: candidates, in: range) else { return nil }
        // A result type that isn't known was reported where it is declared, or as a cycle.
        guard let result = expressions.file.result(of: match.signature, calledAt: range) else { return nil }
        return CheckedExpr(kind: match.signature.target.call(passing: match.arguments), type: result, range: range)
    }

    /// The functions a call of `name` reaches, a struct's initializer among them, reporting it when it reaches
    /// none, unless a declaration of the name failed.
    private func functions(named name: String, at range: SourceRange) -> [Signature] {
        switch expressions.names.lookUp(name, for: .call) {
        // The name's functions are the call's candidates.
        case .functions(let functions):
            return functions

        // A struct's name calls its primary initializer.
        case .type(let initializer):
            return [initializer]

        // A local can't be called.
        case .inScope(.local):
            errors.report(.notAFunction(name: name), at: range)

        // A local whose declaration failed was reported there.
        case .inScope(.failed):
            break

        // Nothing has the name.
        case nil:
            errors.report(.notDeclared(name: name), at: range)
        }
        return []
    }

    /// The one of `candidates` that `arguments` fit, with the arguments checked against its parameters, or nil when
    /// none fits, which is reported unless there are no candidates.
    private func match(_ arguments: [Argument], among candidates: [Signature], in range: SourceRange) -> Match? {
        switch candidates.count {
        // Without a candidate, the arguments are checked for their own errors.
        case 0:
            checkValues(of: arguments)
            return nil

        // One candidate is the call's, if the arguments fit its parameters.
        case 1:
            return check(arguments, against: candidates[0], in: range).map { (candidates[0], $0) }

        // Among overloads, the arguments' labels and types pick one.
        default:
            return pick(among: candidates, for: arguments, in: range)
        }
    }

    /// Checks `arguments` against `signature`'s parameters, in order, reporting each mismatch.
    private func check(_ arguments: [Argument], against signature: Signature,
                       in range: SourceRange) -> [CheckedExpr]? {
        // A call that passes too few or too many arguments fails, though each argument's own errors are reported.
        let parameters = signature.parameters
        guard arguments.count == parameters.count else {
            let takes = ArgumentCount(parameters.count)
            errors.report(.argumentCount(name: signature.name, takes: takes, passes: arguments.count), at: range)
            checkValues(of: arguments)
            return nil
        }

        // Check every argument, so each one's errors are reported, before any failure fails the call.
        let checked = zip(arguments, parameters).map { check($0, against: $1) }
        let values = checked.compactMap { $0 }
        return values.count == arguments.count ? values : nil
    }

    /// Checks `argument`'s label and value against `parameter`.
    private func check(_ argument: Argument, against parameter: Parameter) -> CheckedExpr? {
        let isLabeledRight = argument.label == parameter.label
        // A label other than the parameter's is reported, and the value is still checked.
        if !isLabeledRight {
            let expected = ArgumentLabel(parameter.label)
            errors.report(.argumentLabel(expected: expected, found: ArgumentLabel(argument.label)), at: argument.range)
        }

        // Check the value against the parameter's type.
        let value = checkValue(of: argument, passedTo: parameter)
        // A value that failed, or a parameter whose type isn't known, was reported.
        guard let type = parameter.type, let value else { return nil }
        // So was a value of another type.
        guard expressions.expect(value, type) else { return nil }
        return isLabeledRight ? value : nil
    }

    /// Checks `argument`'s value. An owned parameter takes it, which moves a local's value out of the local.
    private func checkValue(of argument: Argument, passedTo parameter: Parameter) -> CheckedExpr? {
        parameter.convention == .owned ? expressions.checkTaken(argument.value) : expressions.check(argument.value)
    }

    /// The one of `candidates` whose labels and parameter types `arguments` fit, with the checked arguments.
    private func pick(among candidates: [Signature], for arguments: [Argument], in range: SourceRange) -> Match? {
        // Check the arguments on their own, since the candidate that takes them isn't known yet; an Int or a Bool
        // needs nothing from the parameter it is passed to.
        let values = arguments.compactMap { expressions.check($0.value) }
        // An argument that failed was reported, and without its type no candidate can be picked.
        guard values.count == arguments.count else { return nil }

        // Pick the one candidate that takes the arguments' labels and types.
        let typed = zip(arguments, values).map { (label: $0.label, type: $1.type) }
        let fitting = candidates.filter { $0.takes(typed) }
        // No candidate fits.
        if fitting.isEmpty {
            errors.report(.noMatchingFunction(name: candidates[0].name, arguments: spelling(of: typed)), at: range)
        }
        // Two candidates fit only when one names a type that isn't one, which was reported there.
        guard fitting.count == 1 else { return nil }
        return (fitting[0], values)
    }

    /// Checks the values of `arguments` for their own errors, where no function's parameters take them.
    private func checkValues(of arguments: [Argument]) {
        for argument in arguments {
            _ = expressions.check(argument.value)
        }
    }

    /// The arguments as an error writes them, such as `1, by: true` as `Int, by: Bool`.
    private func spelling(of arguments: [TypedArgument]) -> String {
        let written = arguments.map { argument in
            let label = argument.label.map { "\($0): " } ?? ""
            return label + "\(argument.type)"
        }
        return written.joined(separator: ", ")
    }
}
