internal import CLLVM
import RayoIR
import RayoSema
import RayoSource
import RayoSyntax

/// Emits one function's body into an LLVM function, holding each local in a stack slot.
struct FunctionEmitter {
    let function: IRFunction
    let llvmFunction: LLVMValueRef
    /// The program's functions, indexed by `FunctionID`, which calls call.
    let functions: [FunctionValue]
    let program: ProgramEmitter
    private var slots: [LLVMValueRef] = []
    private var blocks: [LLVMBasicBlockRef] = []

    init(function: IRFunction, into llvmFunction: LLVMValueRef, functions: [FunctionValue], program: ProgramEmitter) {
        self.function = function
        self.llvmFunction = llvmFunction
        self.functions = functions
        self.program = program
    }

    var module: ModuleBuilder { program.module }
    var builder: LLVMBuilderRef { program.module.builder }
    var checksOverflow: Bool { program.checksOverflow }

    mutating func emit() {
        LLVMPositionBuilderAtEnd(builder, appendBlock(named: "entry"))
        slots = function.locals.map { LLVMBuildAlloca(builder, llvmType($0), "") }
        for index in 0..<function.parameterCount {
            LLVMBuildStore(builder, LLVMGetParam(llvmFunction, UInt32(index)), slots[index])
        }
        blocks = function.blocks.indices.map { appendBlock(named: "bb\($0)") }
        LLVMBuildBr(builder, blocks[0])
        for (block, llvmBlock) in zip(function.blocks, blocks) {
            LLVMPositionBuilderAtEnd(builder, llvmBlock)
            block.statements.forEach { emit($0) }
            emit(block.terminator)
        }
    }

    /// The type of a local's stack slot.
    private func llvmType(_ type: RayoType) -> LLVMTypeRef {
        precondition(type != .void, "lowering makes no local of type Void")
        return program.llvmType(type)
    }

    func appendBlock(named name: String) -> LLVMBasicBlockRef {
        module.appendBlock(to: llvmFunction, named: name)
    }

    private func emit(_ statement: Statement) {
        let value = compute(statement.value, at: statement.range)
        guard let destination = statement.destination else { return }
        guard let value else { preconditionFailure("lowering stores no call that returns nothing") }
        LLVMBuildStore(builder, value, slots[destination.index])
    }

    private func emit(_ terminator: Terminator) {
        switch terminator {
        case .goto(let target):
            LLVMBuildBr(builder, blocks[target.index])
        case .branch(let condition, let then, let otherwise):
            LLVMBuildCondBr(builder, read(condition), blocks[then.index], blocks[otherwise.index])
        case .return(let result?):
            LLVMBuildRet(builder, read(result))
        case .return(nil):
            LLVMBuildRetVoid(builder)
        case .unreachable:
            LLVMBuildUnreachable(builder)
        }
    }

    private func read(_ operand: Operand) -> LLVMValueRef {
        switch operand {
        case .constant(.int(let value)):
            return module.constant(value)
        case .constant(.bool(let value)):
            return module.constant(value)
        case .local(let local):
            return LLVMBuildLoad2(builder, llvmType(function.locals[local.index]), slots[local.index], "")
        }
    }

    /// Emits the instructions that compute `rvalue`, and returns the LLVM value holding its result, or nil
    /// when it has none.
    private func compute(_ rvalue: Rvalue, at range: SourceRange) -> LLVMValueRef? {
        switch rvalue {
        case .use(let operand):
            return read(operand)
        case .unary(let op, let operand):
            return unary(op, read(operand), at: range)
        case .binary(let op, let leftOperand, let right):
            let left = read(leftOperand)
            return binary(op, left, read(right), at: range)
        case .call(let callee, let arguments):
            let values = arguments.map { read($0) }
            switch callee {
            case .printInt:
                module.call(program.runtime.printInt, [values[0]])
                return nil
            case .function(let id):
                let result = module.call(functions[id.index], values)
                return LLVMTypeOf(result) == module.void ? nil : result
            }
        }
    }

    private func unary(_ op: UnaryOperator, _ operand: LLVMValueRef, at range: SourceRange) -> LLVMValueRef {
        switch op {
        case .negate:
            return arithmetic(.subtract, module.constant(0), operand, at: range)
        case .not:
            return LLVMBuildXor(builder, operand, module.constant(true), "")
        }
    }

    private func binary(_ op: BinaryOperator, _ left: LLVMValueRef, _ right: LLVMValueRef,
                        at range: SourceRange) -> LLVMValueRef {
        switch op {
        case .add: return arithmetic(.add, left, right, at: range)
        case .subtract: return arithmetic(.subtract, left, right, at: range)
        case .multiply: return arithmetic(.multiply, left, right, at: range)
        case .divide: return divide(left, right, at: range)
        case .remainder: return remainder(left, right, at: range)
        case .equal: return compare(LLVMIntEQ, left, right)
        case .notEqual: return compare(LLVMIntNE, left, right)
        case .less: return compare(LLVMIntSLT, left, right)
        case .lessEqual: return compare(LLVMIntSLE, left, right)
        case .greater: return compare(LLVMIntSGT, left, right)
        case .greaterEqual: return compare(LLVMIntSGE, left, right)
        case .and, .or: preconditionFailure("lowering turns '\(op.rawValue)' into branches")
        }
    }

    func compare(_ predicate: LLVMIntPredicate, _ left: LLVMValueRef, _ right: LLVMValueRef) -> LLVMValueRef {
        LLVMBuildICmp(builder, predicate, left, right, "")
    }
}
