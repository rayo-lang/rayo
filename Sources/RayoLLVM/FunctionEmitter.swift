import LLVM
import RayoIR
import RayoSema
import RayoSource

/// Emits one function's body into an LLVM function, holding each local in a stack slot.
struct FunctionEmitter {
    private let function: IRFunction
    private let llvmFunction: Function
    /// The program's functions, indexed by `FunctionID`, that calls go to.
    private let functions: [Function]
    /// The LLVM types of the program's values.
    private let types: LLVMTypes
    private let runtime: RuntimeFunctions
    private let operators: OperatorEmitter
    private var slots: [PointerValue] = []
    private var blocks: [LLVM.BasicBlock] = []

    init(
        function: IRFunction, into llvmFunction: Function, functions: [Function], types: LLVMTypes,
        runtime: RuntimeFunctions,
    ) {
        self.function = function
        self.llvmFunction = llvmFunction
        self.functions = functions
        self.types = types
        self.runtime = runtime
        self.operators = OperatorEmitter(into: llvmFunction, types: types, panic: runtime.panic)
    }

    /// Emits the body into the function, in `program`'s module.
    mutating func emit(in program: borrowing ProgramEmitter) {
        // Make the entry block, and hold each local in a slot there, the parameters holding the arguments.
        program.builder.position(atEndOf: program.context.appendBlock(named: "entry", to: llvmFunction))
        slots = allocateSlots(with: program.builder)
        storeArguments(with: program.builder)

        // Make an LLVM block for each IR block, and go on from the entry block to the first.
        blocks = function.blocks.indices.map { program.context.appendBlock(named: "bb\($0)", to: llvmFunction) }
        program.builder.branch(to: blocks[0])

        // Emit each IR block into the LLVM block made for it.
        for (block, llvmBlock) in zip(function.blocks, blocks) {
            emit(block, into: llvmBlock, in: program)
        }
    }

    /// Allocates a stack slot for each local, and returns the slots in the locals' order.
    private func allocateSlots(with builder: borrowing Builder) -> [PointerValue] {
        function.locals.indices.map { builder.allocate(slotType(of: LocalID(index: $0)), alignment: alignment(of: $0)) }
    }

    /// Stores each argument in its parameter's slot.
    private func storeArguments(with builder: borrowing Builder) {
        // The parameters are the first locals, in order.
        for index in 0..<function.parameterCount {
            store(llvmFunction.parameter(at: index), in: LocalID(index: index), with: builder)
        }
    }

    /// Lowers `local`'s type to the LLVM type of its stack slot.
    private func slotType(of local: LocalID) -> AnyType {
        let type = function.locals[local.index].type
        precondition(type != .void, "lowering makes no local of type Void")
        return types.llvmType(type)
    }

    /// The alignment, in bytes, of the slot of the local at `index`, which is its type's.
    private func alignment(of index: Int) -> Int {
        types.alignment(of: function.locals[index].type)
    }

    /// Emits the instruction that loads `local`'s value from its slot, and returns the value.
    private func load(_ local: LocalID, with builder: borrowing Builder) -> AnyValue {
        builder.load(slotType(of: local), from: slots[local.index], alignment: alignment(of: local.index))
    }

    /// Emits the instruction that stores `value` in `local`'s slot.
    private func store(_ value: AnyValue, in local: LocalID, with builder: borrowing Builder) {
        builder.store(value, to: slots[local.index], alignment: alignment(of: local.index))
    }

    private func emit(
        _ block: RayoIR.BasicBlock, into llvmBlock: LLVM.BasicBlock, in program: borrowing ProgramEmitter,
    ) {
        program.builder.position(atEndOf: llvmBlock)
        for statement in block.statements {
            emit(statement, in: program)
        }
        // The terminator ends the block that the statements leave the builder in.
        emit(block.terminator, in: program)
    }

    private func emit(_ statement: Statement, in program: borrowing ProgramEmitter) {
        switch statement {
        case .compute(let destination, let rvalue, let range):
            emit(rvalue, into: destination, at: range, in: program)

        // A declaration emits nothing: the program reads a slot only once a statement has stored to it.
        case .declare:
            break
        }
    }

    /// Emits the instructions that compute `rvalue`, and stores its result in `destination` when there is one.
    private func emit(
        _ rvalue: Rvalue, into destination: Place?, at range: SourceRange, in program: borrowing ProgramEmitter,
    ) {
        let value = compute(rvalue, at: range, in: program)

        // A value that no local takes is dropped.
        guard let destination else { return }
        // Only a call that returns nothing gives no value.
        guard let value else { preconditionFailure("lowering stores no call that returns nothing") }
        store(value, in: destination.local, with: program.builder)
    }

    private func emit(_ terminator: Terminator, in program: borrowing ProgramEmitter) {
        switch terminator {
        // A `goto` branches to the LLVM block made for its target.
        case .goto(let target):
            program.builder.branch(to: blocks[target.index])

        // A branch picks, on the condition's value, between the LLVM blocks made for its two targets.
        case .branch(let condition, let then, let otherwise):
            // The checker makes every condition a Bool, and LLVM's verifier rejects a module where one isn't.
            let condition = IntValue<I1>(unchecked: read(condition, in: program).ref)
            program.builder.branch(if: condition, then: blocks[then.index], else: blocks[otherwise.index])

        // A `return` with an operand returns its value.
        case .return(let result?):
            program.builder.return(read(result, in: program))

        // A `return` without an operand, from a function that returns Void, returns nothing.
        case .return(nil):
            program.builder.returnVoid()

        // A block that no path reaches ends in LLVM's `unreachable`.
        case .unreachable:
            program.builder.unreachable()
        }
    }

    private func read(_ operand: Operand, in program: borrowing ProgramEmitter) -> AnyValue {
        switch operand {
        // An Int constant needs no instruction: it is an `i64` holding the Int's bits.
        case .constant(.int(let value)):
            types.int64.constant(value).anyValue

        // A Bool constant needs no instruction either: it is an `i1`, 1 for true and 0 for false.
        case .constant(.bool(let value)):
            types.bool.constant(value ? 1 : 0).anyValue

        // A read or a move loads the local from its slot; a move leaves the slot as it is, unread until assigned again.
        case .read(let place), .move(let place):
            load(place.local, with: program.builder)
        }
    }

    /// Emits the instructions that compute `rvalue`, and returns the LLVM value holding its result, or nil
    /// when it has none.
    private func compute(_ rvalue: Rvalue, at range: SourceRange, in program: borrowing ProgramEmitter) -> AnyValue? {
        switch rvalue {
        case .use(let operand):
            read(operand, in: program)
        case .unary(let op, let operand):
            operators.emit(op, on: read(operand, in: program), at: range, in: program)
        case .binary(let op, let left, let right):
            operators.emit(op, read(left, in: program), read(right, in: program), at: range, in: program)
        case .call(let callee, let arguments):
            call(callee, passing: arguments.map { read($0, in: program) }, with: program.builder)
        }
    }

    /// Emits a call of `callee` with `arguments`, and returns its result, or nil when it returns nothing.
    private func call(_ callee: Callee, passing arguments: [AnyValue], with builder: borrowing Builder) -> AnyValue? {
        // Call the LLVM function that `callee` names: the prelude's `print` is the runtime's.
        let function = switch callee {
        case .printInt: runtime.printInt
        case .function(let id): functions[id.index]
        }
        return builder.call(function, arguments)
    }
}
