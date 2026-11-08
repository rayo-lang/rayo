import RayoSyntax

extension BodyChecker {
    mutating func call(_ callee: Expr, _ arguments: [Argument], in range: SourceRange) -> CheckedExpr? {
        guard case .name(let name, let typeArguments) = callee.kind else {
            errors.unsupported("calling \(callee.kind.construct)", at: callee.range)
            return nil
        }
        // A local shadows the function of its name, as any declaration shadows the prelude's.
        if lookUp(name) != nil {
            errors.error("'\(name)' isn't a function", at: callee.range)
            return nil
        }
        guard declarations.functionNames.contains(name) else {
            errors.error("'\(name)' isn't declared", at: callee.range)
            return nil
        }
        guard typeArguments.isEmpty else {
            errors.error("'\(name)' takes no generic arguments", at: callee.range)
            return nil
        }
        guard name == "print" else {
            errors.unsupported("calling 'main'", at: callee.range)
            return nil
        }
        let signature = Signature.print
        guard let checked = check(arguments, against: signature, in: range) else { return nil }
        return CheckedExpr(kind: .call(.printInt, arguments: checked), type: signature.result, range: range)
    }

    /// Checks `arguments` against `signature`'s parameters, one by one and in order. Every argument's value
    /// is checked, whether or not the call matches the signature.
    private mutating func check(_ arguments: [Argument], against signature: Signature,
                                in range: SourceRange) -> [CheckedExpr]? {
        let parameters = signature.parameters
        guard arguments.count == parameters.count else {
            let noun = parameters.count == 1 ? "argument" : "arguments"
            errors.error("'\(signature.name)' takes \(parameters.count) \(noun), but the call passes \(arguments.count)",
                         at: range)
            arguments.forEach { _ = check($0.value) }
            return nil
        }
        var checked: [CheckedExpr] = []
        for (index, (argument, parameter)) in zip(arguments, parameters).enumerated() {
            let labelMatches = labelMatches(argument, parameter, position: index + 1, of: signature)
            if let value = check(argument.value), labelMatches, expect(value, parameter.type) {
                checked.append(value)
            }
        }
        return checked.count == arguments.count ? checked : nil
    }

    /// Whether `argument` has `parameter`'s label, reporting it when it doesn't.
    private mutating func labelMatches(_ argument: Argument, _ parameter: Signature.Parameter, position: Int,
                                       of signature: Signature) -> Bool {
        let argumentName = "argument \(position) of '\(signature.name)'"
        switch (parameter.label, argument.label) {
        case (nil, nil):
            return true
        case (let label?, let written?) where label == written:
            return true
        case (nil, let written?):
            errors.error("\(argumentName) takes no label, not '\(written)'", at: argument.value.range)
        case (let label?, nil):
            errors.error("\(argumentName) needs the label '\(label)'", at: argument.value.range)
        case (let label?, let written?):
            errors.error("\(argumentName) takes the label '\(label)', not '\(written)'", at: argument.value.range)
        }
        return false
    }
}
