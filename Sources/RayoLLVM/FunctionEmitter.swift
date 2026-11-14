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

    let body: IRBody
    /// The function whose body this emits.
    let declaration: FunctionDeclaration
    let llvmFunction: Function
    /// How the function's parameters and result are passed.
    let signature: LoweredSignature
    /// What a call of each of the program's functions reaches, indexed by `FunctionID`.
    let functions: [CallTarget]
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
        body: IRBody, of declaration: FunctionDeclaration, into declared: DeclaredFunction,
        functions: [CallTarget], lowering: SignatureLowering, in program: borrowing ProgramEmitter,
    ) {
        self.body = body
        self.declaration = declaration
        llvmFunction = declared.function
        signature = declared.signature
        self.functions = functions
        self.lowering = lowering
        operators = OperatorEmitter(into: declared.function, types: lowering.types)
        entry = program.context.appendBlock(named: "entry", to: declared.function)
    }

    /// Emits the body into the function, in `program`'s module. Throws where the runtime lacks a function the body
    /// calls.
    mutating func emit(in program: borrowing ProgramEmitter) throws(LLVMError) {
        program.builder.position(atEndOf: entry)
        places = makePlaces(with: program.builder)
        blocks = body.blocks.indices.map { program.context.appendBlock(named: "bb\($0)", to: llvmFunction) }

        for (block, llvmBlock) in zip(body.blocks, blocks) {
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
            use(operand, into: destination, with: program.builder)

        // An operator computes on its operands' values, as their type says.
        case .unary(let op, let operand):
            let type = operand.type(in: body, types: types.table)
            let value = try operators.emit(op, on: read(operand, with: program.builder), of: type, at: range,
                                           in: program)
            keep(value, in: destination, with: program.builder)
        case .binary(let op, let left, let right):
            let type = left.type(in: body, types: types.table)
            let operands = (read(left, with: program.builder), read(right, with: program.builder))
            let value = try operators.emit(op, operands.0, operands.1, of: type, at: range, in: program)
            keep(value, in: destination, with: program.builder)

        // A call passes its arguments as its function's signature says, or builds a struct from them.
        case .call(let callee, let arguments):
            try call(callee, passing: arguments, into: destination, in: program)
        }
    }

    /// Emits the copy of `operand`'s value into `destination`, or nothing where there is no destination, since
    /// reading a place changes nothing.
    private func use(_ operand: Operand, into destination: Place?, with builder: borrowing Builder) {
        let value = value(of: operand, with: builder)

        // A value that no place takes is dropped.
        guard let destination else { return }
        copy(value, to: address(of: destination, with: builder), with: builder)
    }

    /// Emits the store of `value`, an operator's result, in `destination`, where there is one.
    private func keep(_ value: AnyValue, in destination: Place?, with builder: borrowing Builder) {
        // A value that no place takes is dropped.
        guard let destination else { return }
        store(value, at: address(of: destination, with: builder), with: builder)
    }

    private func emit(_ terminator: Terminator, in program: borrowing ProgramEmitter) throws(LLVMError) {
        switch terminator {
        // A `goto` branches to the LLVM block made for its target.
        case .goto(let target):
            program.builder.branch(to: blocks[target.index])

        // A branch picks, on the condition's value, between the LLVM blocks made for its two targets.
        case .branch(let operand, let then, let otherwise):
            let value = read(operand, with: program.builder)
            // The verifier passes no IR that branches on a value that isn't a Bool.
            guard let condition = IntValue<I1>(value) else { preconditionFailure("the IR branches on a non-Bool") }
            program.builder.branch(if: condition, then: blocks[then.index], else: blocks[otherwise.index])

        // A `return` returns its operand's value, or nothing where it has none.
        case .return(let result):
            emitReturn(result, with: program.builder)

        // A block that no path reaches ends in LLVM's `unreachable`.
        case .unreachable:
            program.builder.unreachable()
        }
    }
}
