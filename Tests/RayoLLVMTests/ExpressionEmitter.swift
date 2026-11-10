import CLLVM
@testable import RayoLLVM
import RayoSource
import RayoSyntax

/// Emits an expression of operators, each at `range`, on values and on Int constants.
struct ExpressionEmitter {
    /// The source range of every operator the emitter emits: line 3, columns 7 to 12, of main.rayo.
    static let range = SourceRange(
        SourceLocation(line: 3, column: 7, offset: 20), SourceLocation(line: 3, column: 12, offset: 25),
    )

    let operators: OperatorEmitter

    /// Emits `left op right`.
    func callAsFunction(_ op: BinaryOperator, _ left: LLVMValueRef, _ right: LLVMValueRef) -> LLVMValueRef {
        operators.emit(op, left, right, at: Self.range)
    }

    /// Emits `left op right`, where `right` is an Int constant.
    func callAsFunction(_ op: BinaryOperator, _ left: LLVMValueRef, _ right: Int64) -> LLVMValueRef {
        self(op, left, LLVMConstInt(LLVMTypeOf(left), UInt64(bitPattern: right), 1))
    }

    /// Emits `op operand`.
    func callAsFunction(_ op: UnaryOperator, _ operand: LLVMValueRef) -> LLVMValueRef {
        operators.emit(op, on: operand, at: Self.range)
    }
}
