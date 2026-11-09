import RayoDiagnostics
import RayoSource
import RayoSyntax

extension BodyChecker {
    /// Checks `name(arguments)`. Every argument is checked, whether or not the call matches a function.
    mutating func call(_ name: String, at nameRange: SourceRange, _ arguments: [Argument],
                       in range: SourceRange) -> CheckedExpr? {
        let candidates = functions(named: name, at: nameRange)
        let checked: (signature: Signature, arguments: [CheckedExpr])?
        switch candidates.count {
        case 0:
            arguments.forEach { _ = check($0.value) }
            return nil
        case 1:
            checked = check(arguments, against: candidates[0], in: range).map { (candidates[0], $0) }
        default:
            checked = pick(among: candidates, for: arguments, in: range)
        }
        guard let checked, let result = file.result(of: checked.signature, calledAt: range) else { return nil }
        return CheckedExpr(kind: .call(checked.signature.callee, arguments: checked.arguments), type: result,
                           range: range)
    }

    /// The functions called `name`, reporting it when no function of that name can be called.
    private mutating func functions(named name: String, at range: SourceRange) -> [Signature] {
        switch lookUp(name) {
        case .local:
            errors.report(.notAFunction(name: name), at: range)
            return []
        case .failed:
            return []
        case nil:
            break
        }
        let functions = declarations.functions(named: name)
        if functions.isEmpty { errors.report(.notDeclared(name: name), at: range) }
        return functions
    }

    /// Checks `arguments` against `signature`'s parameters, in order, reporting each mismatch.
    private mutating func check(_ arguments: [Argument], against signature: Signature,
                                in range: SourceRange) -> [CheckedExpr]? {
        let parameters = signature.parameters
        guard arguments.count == parameters.count else {
            let takes = ArgumentCount(parameters.count)
            errors.report(.argumentCount(name: signature.name, takes: takes, passes: arguments.count), at: range)
            arguments.forEach { _ = check($0.value) }
            return nil
        }
        let checked = zip(arguments, parameters).map { check($0, against: $1) }
        let values = checked.compactMap { $0 }
        return values.count == arguments.count ? values : nil
    }

    /// Checks `argument`'s label and value against `parameter`.
    private mutating func check(_ argument: Argument, against parameter: Parameter) -> CheckedExpr? {
        let isLabeledRight = argument.label == parameter.label
        if !isLabeledRight {
            let expected = ArgumentLabel(parameter.label)
            errors.report(.argumentLabel(expected: expected, found: ArgumentLabel(argument.label)), at: argument.range)
        }
        guard let type = parameter.type else {
            _ = check(argument.value)
            return nil
        }
        let value = check(argument.value, expecting: type)
        return isLabeledRight ? value : nil
    }

    /// The one of `candidates` whose labels and parameter types `arguments` fit, with the checked arguments.
    /// Each argument's type is its own, since an Int or a Bool needs nothing from the parameter it is passed to.
    private mutating func pick(among candidates: [Signature], for arguments: [Argument],
                               in range: SourceRange) -> (signature: Signature, arguments: [CheckedExpr])? {
        let values = arguments.compactMap { check($0.value) }
        guard values.count == arguments.count else { return nil }
        let typed = zip(arguments, values).map { (label: $0.label, type: $1.type) }
        let fitting = candidates.filter { $0.takes(typed) }
        if fitting.isEmpty {
            let written = typed.map { ($0.label.map { "\($0): " } ?? "") + "\($0.type)" }.joined(separator: ", ")
            errors.report(.noMatchingFunction(name: candidates[0].name, arguments: written), at: range)
        }
        // Two candidates fit only when one names a type that isn't one, which was reported there.
        guard fitting.count == 1 else { return nil }
        return (fitting[0], values)
    }
}
