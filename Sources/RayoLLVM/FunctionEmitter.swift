internal import CLLVM
import RayoIR
import RayoSema
import RayoSource

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

    private var module: ModuleBuilder { program.module }
    private var builder: LLVMBuilderRef { program.module.builder }
    private var types: LLVMTypes { program.types }
    private var operators: OperatorEmitter { OperatorEmitter(program: program, llvmFunction: llvmFunction) }

    mutating func emit() {
        // An entry block of its own holds the locals' slots and the arguments, then goes to the first block.
        LLVMPositionBuilderAtEnd(builder, appendBlock(named: "entry"))
        slots = function.locals.map { allocateSlot(holding: $0.type) }
        storeArguments()
        blocks = function.blocks.indices.map { appendBlock(named: "bb\($0)") }
        LLVMBuildBr(builder, blocks[0])

        for (block, llvmBlock) in zip(function.blocks, blocks) { emit(block, into: llvmBlock) }
    }

    /// Allocates a stack slot for a local of `type`, aligned as the type is.
    private func allocateSlot(holding type: RayoType) -> LLVMValueRef {
        let slot = LLVMBuildAlloca(builder, llvmType(type), "")!
        LLVMSetAlignment(slot, types.alignment(of: type))
        return slot
    }

    /// Stores each parameter's argument in its slot.
    private func storeArguments() {
        for index in 0..<function.parameterCount {
            store(LLVMGetParam(llvmFunction, UInt32(index)), in: LocalID(index: index))
        }
    }

    /// The type of a local's stack slot.
    private func llvmType(_ type: RayoType) -> LLVMTypeRef {
        precondition(type != .void, "lowering makes no local of type Void")
        return types.llvmType(type)
    }

    /// Emits the instruction that loads `local`'s value from its slot, and returns the value.
    private func load(_ local: LocalID) -> LLVMValueRef {
        let type = function.locals[local.index].type
        let value = LLVMBuildLoad2(builder, llvmType(type), slots[local.index], "")!
        LLVMSetAlignment(value, types.alignment(of: type))
        return value
    }

    /// Emits the instruction that stores `value` in `local`'s slot.
    private func store(_ value: LLVMValueRef, in local: LocalID) {
        let store = LLVMBuildStore(builder, value, slots[local.index])
        LLVMSetAlignment(store, types.alignment(of: function.locals[local.index].type))
    }

    private func appendBlock(named name: String) -> LLVMBasicBlockRef {
        module.appendBlock(to: llvmFunction, named: name)
    }

    private func emit(_ block: BasicBlock, into llvmBlock: LLVMBasicBlockRef) {
        LLVMPositionBuilderAtEnd(builder, llvmBlock)
        for statement in block.statements {
            emit(statement)
        }
        emit(block.terminator)
    }

    private func emit(_ statement: Statement) {
        switch statement {
        // A computation emits its instructions, and stores what it gives where it says.
        case .compute(let destination, let rvalue, let range):
            emit(rvalue, into: destination, at: range)

        // A declaration emits nothing: the slot keeps whatever it holds, and the program reads it only once a
        // statement has stored a value.
        case .declare:
            break
        }
    }

    /// Emits the instructions that compute `rvalue`, and stores its result in `destination` when there is one.
    private func emit(_ rvalue: Rvalue, into destination: Place?, at range: SourceRange) {
        let value = compute(rvalue, at: range)
        // A value that no local takes is dropped.
        guard let destination else { return }
        // Only a call of a function that returns nothing gives no value, and lowering stores none.
        guard let value else { preconditionFailure("lowering stores no call that returns nothing") }
        store(value, in: destination.local)
    }

    private func emit(_ terminator: Terminator) {
        switch terminator {
        // A `goto` branches to its block.
        case .goto(let target):
            LLVMBuildBr(builder, blocks[target.index])

        // A branch goes to one of two blocks, as the condition says.
        case .branch(let condition, let then, let otherwise):
            LLVMBuildCondBr(builder, read(condition), blocks[then.index], blocks[otherwise.index])

        // A `return` with an operand returns its value.
        case .return(let result?):
            LLVMBuildRet(builder, read(result))

        // One without, from a function that returns Void, returns nothing.
        case .return(nil):
            LLVMBuildRetVoid(builder)

        // A block that no path reaches ends in LLVM's `unreachable`.
        case .unreachable:
            LLVMBuildUnreachable(builder)
        }
    }

    private func read(_ operand: Operand) -> LLVMValueRef {
        switch operand {
        case .constant(.int(let value)): return module.constant(value)
        case .constant(.bool(let value)): return module.constant(value)
        // A move leaves the slot as it was: the program reads it again only once it is assigned again.
        case .read(let place), .move(let place): return load(place.local)
        }
    }

    /// Emits the instructions that compute `rvalue`, and returns the LLVM value holding its result, or nil
    /// when it has none.
    private func compute(_ rvalue: Rvalue, at range: SourceRange) -> LLVMValueRef? {
        switch rvalue {
        case .use(let operand): return read(operand)
        case .unary(let op, let operand): return operators.unary(op, read(operand), at: range)
        case .binary(let op, let left, let right): return operators.binary(op, read(left), read(right), at: range)
        case .call(let callee, let arguments): return call(callee, passing: arguments.map { read($0) })
        case .structure(let id, let fields): return structure(id, of: fields.map { read($0) })
        }
    }

    /// Emits the instructions that make a value of the struct `id` of `fields`, its fields' values in the order the
    /// struct declares them, and returns the value. The bytes that pad the struct's end hold nothing.
    private func structure(_ id: StructID, of fields: [LLVMValueRef]) -> LLVMValueRef {
        var value = LLVMGetPoison(types.llvmType(.structure(id)))!
        for (field, fieldValue) in fields.enumerated() {
            value = LLVMBuildInsertValue(builder, value, fieldValue, types.element(holding: field, of: id), "")
        }
        return value
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
