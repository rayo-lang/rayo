import CLLVM
@testable import RayoLLVM
import RayoSyntax

/// Emits an expression of operators, each at `operatorRange`, on values and on Int constants.
struct ExpressionEmitter {
    let operators: OperatorEmitter

    /// Emits `left op right`.
    func callAsFunction(_ op: BinaryOperator, _ left: LLVMValueRef, _ right: LLVMValueRef) -> LLVMValueRef {
        operators.emit(op, left, right, at: operatorRange)
    }

    /// Emits `left op right`, where `right` is an Int constant.
    func callAsFunction(_ op: BinaryOperator, _ left: LLVMValueRef, _ right: Int64) -> LLVMValueRef {
        self(op, left, LLVMConstInt(LLVMTypeOf(left), UInt64(bitPattern: right), 1))
    }

    /// Emits `op operand`.
    func callAsFunction(_ op: UnaryOperator, _ operand: LLVMValueRef) -> LLVMValueRef {
        operators.emit(op, on: operand, at: operatorRange)
    }
}
