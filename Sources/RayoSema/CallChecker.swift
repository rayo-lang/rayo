import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks a call by name: which function or struct's initializer it reaches, and a function's arguments against its
/// parameters.
struct CallChecker {
    /// A function that a call reaches, and the call's arguments, checked against its parameters.
    private typealias Match = (signature: Signature, arguments: [CheckedExpr])

    /// An argument's label and the type of its value, which choose among overloads.
    private typealias TypedArgument = (label: String?, type: RayoType)

    let expressions: ExpressionChecker

    private var errors: ErrorList { expressions.file.errors }

    /// Checks `name(arguments)`. Every argument is checked, whether or not the call reaches a function or a struct.
    func call(_ name: String, at nameRange: SourceRange, _ arguments: [Argument],
              in range: SourceRange) -> CheckedExpr? {
        switch expressions.names.lookUp(name, for: .call) {
        // A struct's name calls the struct's primary initializer.
        case .structure(let id):
            return InitializerChecker(expressions: expressions).make(id, from: arguments, in: range)

        // The name's functions are the call's candidates.
        case .functions(let functions):
            return call(among: functions, passing: arguments, in: range)

        // A local can't be called.
        case .inScope(.local):
            errors.report(.notAFunction(name: name), at: nameRange)

        // A local whose declaration failed was reported there.
        case .inScope(.failed):
            break

        // Nothing has the name.
        case nil:
            errors.report(.notDeclared(name: name), at: nameRange)
        }

        // A call that reaches neither still has each argument's own errors reported.
        checkValues(of: arguments)
        return nil
    }

    /// Checks a call of one of `candidates`, the functions of one name, that passes `arguments`.
    private func call(among candidates: [Signature], passing arguments: [Argument],
                      in range: SourceRange) -> CheckedExpr? {
        // A call whose arguments fit no candidate was reported.
        guard let match = match(arguments, among: candidates, in: range) else { return nil }

        // A result type that isn't known was reported in the function that gives it, or here as a cycle.
        guard let result = expressions.file.result(of: match.signature, calledAt: range) else { return nil }
        let kind = CheckedExprKind.call(match.signature.callee, arguments: match.arguments)
        return CheckedExpr(kind: kind, type: result, range: range)
    }

    /// The one of `candidates` that `arguments` fit, with the arguments checked against its parameters.
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
        // A label other than the parameter's is reported, and fails the argument once its value is checked.
        let isLabeledRight = argument.label == parameter.label
        if !isLabeledRight {
            let expected = ArgumentLabel(parameter.label)
            errors.report(.argumentLabel(expected: expected, found: ArgumentLabel(argument.label)), at: argument.range)
        }

        // A parameter whose type isn't known was reported where it is declared; the value is checked on its own.
        guard let type = parameter.type else {
            _ = expressions.check(argument.value)
            return nil
        }
        let value = expressions.check(argument.value, expecting: type)
        return isLabeledRight ? value : nil
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
        // No candidate fits, which is reported with the arguments' types.
        if fitting.isEmpty {
            errors.report(.noMatchingFunction(name: candidates[0].name, arguments: spelling(of: typed)), at: range)
        }
        // None fit, which was reported; two fit only when one names a type that isn't one, which was reported there.
        guard fitting.count == 1 else { return nil }
        return (fitting[0], values)
    }

    /// Checks the values of `arguments` for their own errors, where no function's parameters take them.
    private func checkValues(of arguments: [Argument]) {
        for argument in arguments {
            _ = expressions.check(argument.value)
        }
    }

    /// The arguments as an error writes them, such as `Int, by: Bool`.
    private func spelling(of arguments: [TypedArgument]) -> String {
        let written = arguments.map { argument in
            let label = argument.label.map { "\($0): " } ?? ""
            return label + "\(argument.type)"
        }
        return written.joined(separator: ", ")
    }
}
