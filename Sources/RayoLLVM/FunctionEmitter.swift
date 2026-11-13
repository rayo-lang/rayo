import LLVM
import RayoIR
import RayoSema
import RayoSource

/// Emits one function's body into an LLVM function. Each local lies in a place of its own: a stack slot, or the
/// memory a pointer the function is passed points to.
struct FunctionEmitter {
    /// A pointer to a place, a local's or a field inside it, and the type of the value there.
    struct Address {
        var pointer: PointerValue
        var type: RayoType
    }

    /// The value an operand gives: a constant, or the place that holds it, which is read only where it is used.
    enum OperandValue {
        case constant(AnyValue, RayoType)
        case place(Address)

        var type: RayoType {
            switch self {
            case .constant(_, let type): type
            case .place(let address): address.type
            }
        }
    }

    let function: IRFunction
    let llvmFunction: Function
    /// How the function's parameters and result are passed.
    let signature: LoweredSignature
    let callees: Callees
    /// The rules that say how values are passed, and which are small.
    let lowering: SignatureLowering
    let operators: OperatorEmitter
    /// The block that holds every stack slot, and goes on to the first IR block.
    let entry: LLVM.BasicBlock
    /// The pointer to each local's place, indexed by `LocalID`.
    var places: [PointerValue] = []
    var blocks: [LLVM.BasicBlock] = []

    /// The LLVM types of the program's values.
    var types: LLVMTypes { lowering.types }

    init(
        function: IRFunction, into declared: DeclaredFunction, callees: Callees, lowering: SignatureLowering,
        panic: Function, in program: borrowing ProgramEmitter,
    ) {
        self.function = function
        llvmFunction = declared.function
        signature = declared.signature
        self.callees = callees
        self.lowering = lowering
        operators = OperatorEmitter(into: declared.function, types: lowering.types, panic: panic)
        entry = program.context.appendBlock(named: "entry", to: declared.function)
    }

    /// Emits the body into the function, in `program`'s module. Throws where the IR gives an instruction a value of a
    /// type it doesn't take.
    mutating func emit(in program: borrowing ProgramEmitter) throws(LLVMError) {
        program.builder.position(atEndOf: entry)
        places = try makePlaces(with: program.builder)
        blocks = function.blocks.indices.map { program.context.appendBlock(named: "bb\($0)", to: llvmFunction) }

        for (block, llvmBlock) in zip(function.blocks, blocks) {
            try emit(block, into: llvmBlock, in: program)
        }

        enterFirstBlock(with: program.builder)
    }

    /// Ends the entry block, once the body has allocated every slot it needs there, by going on to the first IR
    /// block.
    private func enterFirstBlock(with builder: borrowing Builder) {
        builder.position(atEndOf: entry)
        builder.branch(to: blocks[0])
    }

    private func emit(
        _ block: RayoIR.BasicBlock, into llvmBlock: LLVM.BasicBlock, in program: borrowing ProgramEmitter,
    ) throws(LLVMError) {
        program.builder.position(atEndOf: llvmBlock)
        for statement in block.statements {
            try emit(statement, in: program)
        }
        // The terminator ends the block that the statements leave the builder in.
        try emit(block.terminator, in: program)
    }

    private func emit(_ statement: Statement, in program: borrowing ProgramEmitter) throws(LLVMError) {
        switch statement {
        case .compute(let destination, let rvalue, let range):
            try emit(rvalue, into: destination?.place, at: range, in: program)

        // A declaration emits nothing: the program reads a place only once a statement has stored to it.
        case .declare:
            break
        }
    }

    /// Emits the instructions that compute `rvalue`, and stores its result in `destination` when there is one.
    private func emit(
        _ rvalue: Rvalue, into destination: Place?, at range: SourceRange, in program: borrowing ProgramEmitter,
    ) throws(LLVMError) {
        switch rvalue {
        // A use copies its operand's value.
        case .use(let operand):
            try use(operand, into: destination, with: program.builder)

        // An operator computes on its operands' values.
        case .unary(let op, let operand):
            let value = try operators.emit(op, on: read(operand, with: program.builder), at: range, in: program)
            try keep(value, in: destination, with: program.builder)
        case .binary(let op, let left, let right):
            let operands = try (read(left, with: program.builder), read(right, with: program.builder))
            let value = try operators.emit(op, operands.0, operands.1, at: range, in: program)
            try keep(value, in: destination, with: program.builder)

        // A call passes its arguments as its function's signature says.
        case .call(let callee, let arguments):
            try call(callee, passing: arguments, into: destination, with: program.builder)

        // A struct is built in its place, one field at a time.
        case .structure(let id, let fields):
            try build(id, from: fields, into: destination, with: program.builder)
        }
    }

    /// Emits the copy of `operand`'s value into `destination`, or nothing where there is no destination, since
    /// reading a place changes nothing.
    private func use(_ operand: Operand, into destination: Place?, with builder: borrowing Builder) throws(LLVMError) {
        let value = try value(of: operand, with: builder)

        // A value that no place takes is dropped.
        guard let destination else { return }
        try copy(value, to: address(of: destination, with: builder), with: builder)
    }

    /// Emits the store of `value`, an operator's result, in `destination`, where there is one.
    private func keep(_ value: AnyValue, in destination: Place?, with builder: borrowing Builder) throws(LLVMError) {
        // A value that no place takes is dropped.
        guard let destination else { return }
        try store(value, at: address(of: destination, with: builder), with: builder)
    }

    private func emit(_ terminator: Terminator, in program: borrowing ProgramEmitter) throws(LLVMError) {
        switch terminator {
        // A `goto` branches to the LLVM block made for its target.
        case .goto(let target):
            program.builder.branch(to: blocks[target.index])

        // A branch picks, on the condition's value, between the LLVM blocks made for its two targets.
        case .branch(let operand, let then, let otherwise):
            let value = try read(operand, with: program.builder)
            // A condition that isn't a Bool, which the checker passes no IR with, fails here, saying what it is.
            guard let condition = IntValue<I1>(value) else {
                throw LLVMError(message: "the IR branches on a value of type \(value.type.text), where it takes i1")
            }
            program.builder.branch(if: condition, then: blocks[then.index], else: blocks[otherwise.index])

        // A `return` returns its operand's value, or nothing where it has none.
        case .return(let result):
            try emitReturn(result, with: program.builder)

        // A block that no path reaches ends in LLVM's `unreachable`.
        case .unreachable:
            program.builder.unreachable()
        }
    }
}
