import RayoCheckedProgram

/// What a call does once it has chosen the signature it reaches: call a function, or make an array.
enum CallTarget {
    /// A function the file declares, or a built-in, which the call calls with its arguments.
    case callee(Callee)
    /// An array's `init(repeating:)`, which makes the array with each element a copy of the call's one argument.
    case filledArray

    /// The checked call that passes `arguments`, each settled to its parameter's type, to the target, whose
    /// parameters are `parameters`.
    func call(passing arguments: [CheckedExpr], to parameters: [Parameter]) -> CheckedExprKind {
        switch self {
        case .callee(let callee):
            .call(callee, arguments: zip(arguments, parameters).map { CheckedArgument(passing: $0, as: $1.convention) })
        case .filledArray:
            .filledArray(arguments[0])
        }
    }
}
