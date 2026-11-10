import CLLVM
@testable import RayoLLVM
import RayoSyntax

/// What a release build's optimiser made of an operation on two Ints it knows: the Int it gave, a result LLVM
/// leaves undefined, or none it could compute.
enum Folding: Equatable {
    case defined(Int64)
    case undefined
    case unfolded
}

/// What a release build's optimiser folds `left op right` to.
func folding(of op: BinaryOperator, _ left: Int64, _ right: Int64) throws -> Folding {
    // Have the optimiser compute the operator, emitted in `g` on parameters, once it inlines `f`'s call of `g`.
    let module = try OperatorModule(for: .release)
    let (operation, _) = module.define("g", on: .ints) { emit, a, b in emit(op, a, b) }
    let caller = module.defineCall("f", of: operation, left, right)
    // `g` is exported too, since a hidden `g` would let the optimiser specialise it on one constant first, and
    // rewrite an operation LLVM leaves undefined before it sees the other.
    try module.ready(exporting: ["f", "g"])

    // Where the optimiser left `f` no `ret`, every path through it reaches behaviour LLVM leaves undefined.
    guard let returned = returnedValue(of: caller.value) else { return .undefined }
    // An Int constant is the result the optimiser computed.
    if LLVMIsAConstantInt(returned) != nil { return .defined(LLVMConstIntGetSExtValue(returned)) }
    // LLVM counts poison as undef, and either is a result it leaves undefined.
    if LLVMIsUndef(returned) != 0 { return .undefined }
    // Anything else is a result the optimiser couldn't compute.
    return .unfolded
}

/// The value the first `ret` among `function`'s blocks returns, or nil where none of its blocks returns.
private func returnedValue(of function: LLVMValueRef) -> LLVMValueRef? {
    var block = LLVMGetFirstBasicBlock(function)
    while let current = block {
        // A block that ends in a `ret` holds the returned value as the `ret`'s operand.
        if let end = LLVMGetBasicBlockTerminator(current), LLVMGetInstructionOpcode(end) == LLVMRet {
            return LLVMGetOperand(end, 0)
        }
        block = LLVMGetNextBasicBlock(current)
    }
    return nil
}
