import RayoDiagnostics
import RayoSource
import RayoSyntax

extension BodyChecker {
    /// Checks `name(arguments)`. Every argument is checked, whether or not the call matches the function.
    mutating func call(_ name: String, at nameRange: SourceRange, _ arguments: [Expr],
                       in range: SourceRange) -> CheckedExpr? {
        guard let signature = signature(of: name, at: nameRange) else {
            arguments.forEach { _ = check($0) }
            return nil
        }
        guard let checked = check(arguments, against: signature, in: range) else { return nil }
        return CheckedExpr(kind: .call(.printInt, arguments: checked), type: signature.result, range: range)
    }

    /// The signature of the function called `name`, reporting it when no function of that name can be called.
    private mutating func signature(of name: String, at range: SourceRange) -> Signature? {
        switch lookUp(name) {
        case .local:
            errors.report(.notAFunction(name: name), at: range)
            return nil
        case .failed:
            return nil
        case nil:
            break
        }
        guard declarations.functionNames.contains(name) else {
            errors.report(.notDeclared(name: name), at: range)
            return nil
        }
        guard name == "print" else {
            errors.report(.notCallable(name: name), at: range)
            return nil
        }
        return .print
    }

    /// Checks `arguments` against `signature`'s parameter types, in order.
    private mutating func check(_ arguments: [Expr], against signature: Signature,
                                in range: SourceRange) -> [CheckedExpr]? {
        let parameters = signature.parameters
        guard arguments.count == parameters.count else {
            let takes = ArgumentCount(parameters.count)
            errors.report(.argumentCount(name: signature.name, takes: takes, passes: arguments.count), at: range)
            arguments.forEach { _ = check($0) }
            return nil
        }
        let checked = zip(arguments, parameters).compactMap { check($0, expecting: $1) }
        return checked.count == arguments.count ? checked : nil
    }
}
