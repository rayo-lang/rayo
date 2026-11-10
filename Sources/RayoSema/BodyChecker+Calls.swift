import RayoDiagnostics
import RayoSource
import RayoSyntax

extension BodyChecker {
    /// Checks `name(arguments)`. Every argument is checked, whether or not the call matches a function.
    mutating func call(_ name: String, at nameRange: SourceRange, _ arguments: [Argument],
                       in range: SourceRange) -> CheckedExpr? {
        // Find the functions the call can reach, and the one its arguments fit.
        let candidates = functions(named: name, at: nameRange)
        let checked: (signature: Signature, arguments: [CheckedExpr])?
        switch candidates.count {
        // Without a candidate, the arguments are checked for their own errors.
        case 0:
            arguments.forEach { _ = check($0.value) }
            return nil

        // One candidate is the call's, if the arguments fit its parameters.
        case 1:
            checked = check(arguments, against: candidates[0], in: range).map { (candidates[0], $0) }

        // Among overloads, the arguments' labels and types pick one.
        default:
            checked = pick(among: candidates, for: arguments, in: range)
        }

        // A call whose arguments fit no function, or whose result type isn't known, was reported.
        guard let checked, let result = file.result(of: checked.signature, calledAt: range) else { return nil }
        return CheckedExpr(kind: .call(checked.signature.callee, arguments: checked.arguments), type: result,
                           range: range)
    }

    /// The functions a call of `name` reaches, reporting it when it reaches none, unless a declaration of the name
    /// failed.
    private mutating func functions(named name: String, at range: SourceRange) -> [Signature] {
        switch lookUp(name, for: .call) {
        // The name's functions are the call's candidates.
        case .functions(let functions):
            return functions

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

    /// Checks `arguments` against `signature`'s parameters, in order, reporting each mismatch.
    private mutating func check(_ arguments: [Argument], against signature: Signature,
                                in range: SourceRange) -> [CheckedExpr]? {
        // A call that passes too few or too many arguments fails, though each argument's own errors are reported.
        let parameters = signature.parameters
        guard arguments.count == parameters.count else {
            let takes = ArgumentCount(parameters.count)
            errors.report(.argumentCount(name: signature.name, takes: takes, passes: arguments.count), at: range)
            arguments.forEach { _ = check($0.value) }
            return nil
        }

        // Check every argument, so each one's errors are reported, before any failure fails the call.
        let checked = zip(arguments, parameters).map { check($0, against: $1) }
        let values = checked.compactMap { $0 }
        return values.count == arguments.count ? values : nil
    }

    /// Checks `argument`'s label and value against `parameter`.
    private mutating func check(_ argument: Argument, against parameter: Parameter) -> CheckedExpr? {
        // A label other than the parameter's is reported, and fails the argument once its value is checked.
        let isLabeledRight = argument.label == parameter.label
        if !isLabeledRight {
            let expected = ArgumentLabel(parameter.label)
            errors.report(.argumentLabel(expected: expected, found: ArgumentLabel(argument.label)), at: argument.range)
        }

        // A parameter whose type isn't known was reported where it is declared; the value is checked on its own.
        guard let type = parameter.type else {
            _ = check(argument.value)
            return nil
        }
        let value = check(argument.value, expecting: type)
        return isLabeledRight ? value : nil
    }

    /// The one of `candidates` whose labels and parameter types `arguments` fit, with the checked arguments.
    private mutating func pick(among candidates: [Signature], for arguments: [Argument],
                               in range: SourceRange) -> (signature: Signature, arguments: [CheckedExpr])? {
        // Check the arguments on their own, since the candidate that takes them isn't known yet; an Int or a Bool
        // needs nothing from the parameter it is passed to.
        let values = arguments.compactMap { check($0.value) }
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

    /// The arguments as an error writes them, such as `Int, by: Bool`.
    private func spelling(of arguments: [(label: String?, type: RayoType)]) -> String {
        let written = arguments.map { argument in
            let label = argument.label.map { "\($0): " } ?? ""
            return label + "\(argument.type)"
        }
        return written.joined(separator: ", ")
    }
}
