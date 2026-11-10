internal import CLLVM
import RayoIR
import RayoSema
import RayoSource

/// Emits one function's body into an LLVM function, holding each local in a stack slot.
struct FunctionEmitter {
    private let function: IRFunction
    private let llvmFunction: LLVMValueRef
    /// The program's functions, indexed by `FunctionID`, that calls go to.
    private let functions: [FunctionValue]
    private let program: ProgramEmitter
    private let operators: OperatorEmitter
    private var slots: [LLVMValueRef] = []
    private var blocks: [LLVMBasicBlockRef] = []

    init(function: IRFunction, into llvmFunction: LLVMValueRef, functions: [FunctionValue], program: ProgramEmitter) {
        self.function = function
        self.llvmFunction = llvmFunction
        self.functions = functions
        self.program = program
        self.operators = OperatorEmitter(program: program, into: llvmFunction)
    }

    private var module: ModuleBuilder { program.module }
    private var builder: LLVMBuilderRef { module.builder }
    private var types: LLVMTypes { program.types }

    mutating func emit() {
        // Make the entry block, and hold each local in a slot there, the parameters holding the arguments.
        LLVMPositionBuilderAtEnd(builder, appendBlock(named: "entry"))
        slots = allocateSlots()
        storeArguments()

        // Make an LLVM block for each IR block, and go on from the entry block to the first.
        blocks = function.blocks.indices.map { appendBlock(named: "bb\($0)") }
        LLVMBuildBr(builder, blocks[0])

        // Emit each IR block into the LLVM block made for it.
        for (block, llvmBlock) in zip(function.blocks, blocks) {
            emit(block, into: llvmBlock)
        }
    }

    /// Allocates a stack slot for each local, and returns the slots in the locals' order.
    private func allocateSlots() -> [LLVMValueRef] {
        function.locals.indices.map { LLVMBuildAlloca(builder, slotType(of: LocalID(index: $0)), "") }
    }

    /// Stores each argument in its parameter's slot.
    private func storeArguments() {
        // The parameters are the first locals, in order.
        for index in 0..<function.parameterCount {
            store(LLVMGetParam(llvmFunction, UInt32(index)), in: LocalID(index: index))
        }
    }

    /// Lowers `local`'s type to the LLVM type of its stack slot.
    private func slotType(of local: LocalID) -> LLVMTypeRef {
        let type = function.locals[local.index].type
        precondition(type != .void, "lowering makes no local of type Void")
        return types.llvmType(type)
    }

    /// Emits the instruction that loads `local`'s value from its slot, and returns the value.
    private func load(_ local: LocalID) -> LLVMValueRef {
        LLVMBuildLoad2(builder, slotType(of: local), slots[local.index], "")
    }

    /// Emits the instruction that stores `value` in `local`'s slot.
    private func store(_ value: LLVMValueRef, in local: LocalID) {
        LLVMBuildStore(builder, value, slots[local.index])
    }

    private func appendBlock(named name: String) -> LLVMBasicBlockRef {
        module.appendBlock(to: llvmFunction, named: name)
    }

    private func emit(_ block: BasicBlock, into llvmBlock: LLVMBasicBlockRef) {
        LLVMPositionBuilderAtEnd(builder, llvmBlock)
        for statement in block.statements {
            emit(statement)
        }
        // The terminator ends the block that the statements leave the builder in.
        emit(block.terminator)
    }

    private func emit(_ statement: Statement) {
        switch statement {
        case .compute(let destination, let rvalue, let range):
            emit(rvalue, into: destination, at: range)

        // A declaration emits nothing: the program reads a slot only once a statement has stored to it.
        case .declare:
            break
        }
    }

    /// Emits the instructions that compute `rvalue`, and stores its result in `destination` when there is one.
    private func emit(_ rvalue: Rvalue, into destination: Place?, at range: SourceRange) {
        let value = compute(rvalue, at: range)

        // A value that no local takes is dropped.
        guard let destination else { return }
        // Only a call that returns nothing gives no value.
        guard let value else { preconditionFailure("lowering stores no call that returns nothing") }
        store(value, in: destination.local)
    }

    private func emit(_ terminator: Terminator) {
        switch terminator {
        // A `goto` branches to the LLVM block made for its target.
        case .goto(let target):
            LLVMBuildBr(builder, blocks[target.index])

        // A branch picks, on the condition's value, between the LLVM blocks made for its two targets.
        case .branch(let condition, let then, let otherwise):
            LLVMBuildCondBr(builder, read(condition), blocks[then.index], blocks[otherwise.index])

        // A `return` with an operand returns its value.
        case .return(let result?):
            LLVMBuildRet(builder, read(result))

        // A `return` without an operand, from a function that returns Void, returns nothing.
        case .return(nil):
            LLVMBuildRetVoid(builder)

        // A block that no path reaches ends in LLVM's `unreachable`.
        case .unreachable:
            LLVMBuildUnreachable(builder)
        }
    }

    private func read(_ operand: Operand) -> LLVMValueRef {
        switch operand {
        // An Int constant needs no instruction: it is an `i64` holding the Int's bits.
        case .constant(.int(let value)):
            return module.constant(value)

        // A Bool constant needs no instruction either: it is an `i1`, 1 for true and 0 for false.
        case .constant(.bool(let value)):
            return module.constant(value)

        // A read or a move loads the local from its slot; a move leaves the slot as it is, unread until assigned again.
        case .read(let place), .move(let place):
            return load(place.local)
        }
    }

    /// Emits the instructions that compute `rvalue`, and returns the LLVM value holding its result, or nil
    /// when it has none.
    private func compute(_ rvalue: Rvalue, at range: SourceRange) -> LLVMValueRef? {
        switch rvalue {
        case .use(let operand): return read(operand)
        case .unary(let op, let operand): return operators.emit(op, on: read(operand), at: range)
        case .binary(let op, let left, let right): return operators.emit(op, read(left), read(right), at: range)
        case .call(let callee, let arguments): return call(callee, passing: arguments.map { read($0) })
        }
    }

    /// Emits a call of `callee` with `arguments`, and returns its result, or nil when it returns nothing.
    private func call(_ callee: Callee, passing arguments: [LLVMValueRef]) -> LLVMValueRef? {
        switch callee {
        // The prelude's `print` calls the runtime's, and returns nothing.
        case .printInt:
            module.call(program.runtime.printInt, [arguments[0]])
            return nil

        // A call of one of the program's functions returns what the function does, unless that is nothing.
        case .function(let id):
            let result = module.call(functions[id.index], arguments)
            return LLVMTypeOf(result) == module.void ? nil : result
        }
    }
}
