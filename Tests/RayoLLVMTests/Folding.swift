import LLVM
@testable import RayoLLVM
import RayoIR

/// What a release build's optimiser made of an operation on two Ints it knows: the Int it gave, a result LLVM
/// leaves undefined, or none it could compute.
enum Folding: Equatable {
    case defined(Int64)
    case undefined
    case unfolded
}

/// What a release build's optimiser folds `left op right` to.
func folding(of op: IRBinaryOperator, _ left: Int64, _ right: Int64) throws -> Folding {
    // Have the optimiser compute the operator, emitted in `g` on parameters, once it inlines `f`'s call of `g`.
    var module = try OperatorModule(for: .release)
    let (operation, _) = try module.define("g", on: .ints) { emit, a, b in try emit(op, a, b) }
    let caller = module.defineCall("f", of: operation, left, right)
    // `g` is exported too, since a hidden `g` would let the optimiser specialise it on one constant first, and
    // rewrite an operation LLVM leaves undefined before it sees the other.
    try module.ready(exporting: ["f", "g"])

    // `f` and its instructions belong to the module, so it lives until they have been read.
    return withExtendedLifetime(module) { folding(returnedBy: caller) }
}

/// What the optimiser folds `function`'s result to.
private func folding(returnedBy function: Function) -> Folding {
    // Where the optimiser left `function` no `ret`, every path through it reaches behaviour LLVM leaves undefined.
    guard let returned = returnedValue(of: function) else { return .undefined }

    return if let result = IntValue<I64>(returned)?.constantValue {
        // An Int constant is the result the optimiser computed.
        .defined(result)
    } else if returned.isUndefined {
        // Undef and poison are results LLVM leaves undefined.
        .undefined
    } else {
        // Anything else is a result the optimiser couldn't compute.
        .unfolded
    }
}

/// The value the first `ret` among `function`'s blocks returns, or nil where none of its blocks returns.
private func returnedValue(of function: Function) -> AnyValue? {
    // A block that ends in a `ret` holds the returned value as the `ret`'s operand.
    let returning = function.blocks.lazy.compactMap(\.terminator).first { $0.opcode == .return }
    return returning?.operand(at: 0)
}
