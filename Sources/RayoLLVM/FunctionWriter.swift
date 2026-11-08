import RayoIR
import RayoSema
import RayoSyntax

/// Writes one function's body, holding each local in a stack slot.
struct FunctionWriter {
    let function: IRFunction
    var module: ModuleWriter
    var lines: [String] = []
    var nextValue = 0
    var nextLabel = 0

    init(function: IRFunction, module: ModuleWriter) {
        self.function = function
        self.module = module
    }

    var checksOverflow: Bool { module.checksOverflow }

    mutating func write() -> String {
        lines.append("entry:")
        for (index, type) in function.locals.enumerated() {
            lines.append("  %l\(index) = alloca \(llvmType(type))")
        }
        lines.append("  br label %bb0")
        for (index, block) in function.blocks.enumerated() {
            lines.append("bb\(index):")
            block.statements.forEach { write($0) }
            write(block.terminator)
        }
        return lines.map { $0 + "\n" }.joined()
    }

    /// The type of a local's stack slot.
    private func llvmType(_ type: RayoType) -> String {
        switch type {
        case .int: return "i64"
        case .void: preconditionFailure("lowering makes no local of type Void")
        }
    }

    mutating func newValue() -> String {
        defer { nextValue += 1 }
        return "%v\(nextValue)"
    }

    mutating func newLabel() -> String {
        defer { nextLabel += 1 }
        return "check\(nextLabel)"
    }

    mutating func emit(_ line: String) {
        lines.append("  " + line)
    }

    private mutating func write(_ statement: Statement) {
        let value = compute(statement.value, at: statement.range)
        guard let destination = statement.destination else { return }
        guard let value else { preconditionFailure("lowering stores no call that returns nothing") }
        emit("store \(llvmType(function.locals[destination.index])) \(value), ptr %l\(destination.index)")
    }

    private mutating func write(_ terminator: Terminator) {
        switch terminator {
        case .return:
            emit("ret void")
        }
    }

    private mutating func read(_ operand: Operand) -> String {
        switch operand {
        case .constant(let value):
            return String(value)
        case .local(let local):
            let value = newValue()
            emit("\(value) = load \(llvmType(function.locals[local.index])), ptr %l\(local.index)")
            return value
        }
    }

    /// Emits the instructions that compute `rvalue`, and returns the LLVM value holding its result, or nil
    /// when it has none.
    private mutating func compute(_ rvalue: Rvalue, at range: SourceRange) -> String? {
        switch rvalue {
        case .use(let operand):
            return read(operand)
        case .unary(let op, let operand):
            return unary(op, read(operand), at: range)
        case .binary(let op, let left, let right):
            let left = read(left)
            return binary(op, left, read(right), at: range)
        case .call(let callee, let arguments):
            let values = arguments.map { read($0) }
            switch callee {
            case .printInt:
                emit("call i32 (ptr, ...) @printf(ptr @rayo.int_format, i64 \(values[0]))")
                return nil
            }
        }
    }

    private mutating func unary(_ op: UnaryOperator, _ operand: String, at range: SourceRange) -> String {
        switch op {
        case .negate: return arithmetic("sub", "0", operand, at: range)
        case .not: preconditionFailure("the checker gives '!' no integer operand")
        }
    }

    private mutating func binary(_ op: BinaryOperator, _ left: String, _ right: String, at range: SourceRange) -> String {
        switch op {
        case .add: return arithmetic("add", left, right, at: range)
        case .subtract: return arithmetic("sub", left, right, at: range)
        case .multiply: return arithmetic("mul", left, right, at: range)
        case .divide: return divide(left, right, at: range)
        case .remainder: return remainder(left, right, at: range)
        default: preconditionFailure("the checker accepts no '\(op.rawValue)'")
        }
    }
}
