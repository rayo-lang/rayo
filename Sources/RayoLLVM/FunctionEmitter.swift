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

    /// Emits the body into the function, in `program`'s module. Throws where the IR gives an instruction a value of a
    /// type it doesn't take.
    mutating func emit(in program: borrowing ProgramEmitter) throws(LLVMError) {
        // Make the entry block, and hold each local in a slot there, the parameters holding the arguments.
        program.builder.position(atEndOf: program.context.appendBlock(named: "entry", to: llvmFunction))
        slots = allocateSlots(with: program.builder)
        try storeArguments(with: program.builder)

        // Make an LLVM block for each IR block, and go on from the entry block to the first.
        blocks = function.blocks.indices.map { program.context.appendBlock(named: "bb\($0)", to: llvmFunction) }
        program.builder.branch(to: blocks[0])

        // Emit each IR block into the LLVM block made for it.
        for (block, llvmBlock) in zip(function.blocks, blocks) {
            try emit(block, into: llvmBlock, in: program)
        }
    }

    /// Allocates a stack slot for each local, and returns the slots in the locals' order.
    private func allocateSlots(with builder: borrowing Builder) -> [PointerValue] {
        function.locals.indices.map { index in
            let local = LocalID(index: index)
            return builder.allocate(slotType(of: local), alignment: alignment(of: local))
        }
    }

    /// Stores each argument in its parameter's slot.
    private func storeArguments(with builder: borrowing Builder) throws(LLVMError) {
        // The parameters are the first locals, in order.
        for index in 0..<function.parameterCount {
            try store(llvmFunction.parameter(at: index), in: LocalID(index: index), with: builder)
        }
    }

    /// Lowers `local`'s type to the LLVM type of its stack slot.
    private func slotType(of local: LocalID) -> AnyType {
        let type = function.locals[local.index].type
        precondition(type != .void, "lowering makes no local of type Void")
        return types.llvmType(type)
    }

    /// The alignment, in bytes, of `local`'s slot, which is its type's.
    private func alignment(of local: LocalID) -> Int {
        types.alignment(of: function.locals[local.index].type)
    }

    /// Emits the instructions that load the value at `place`, a local's slot or a field inside it, and returns the
    /// value. Throws where the place names a field that the value holding it doesn't have.
    private func load(_ place: Place, with builder: borrowing Builder) throws(LLVMError) -> AnyValue {
        // Start at the local's slot, and step into each field in turn.
        var pointer = slots[place.local.index]
        var type = function.locals[place.local.index].type
        for field in place.fields {
            (pointer, type) = try fieldPointer(to: field, of: type, at: pointer, with: builder)
        }

        // A value lies in memory aligned as its type is, a field too, since its struct's layout keeps it so.
        return builder.load(types.llvmType(type), from: pointer, alignment: types.alignment(of: type))
    }

    /// Emits the instruction that gives a pointer to the field at `field`, its place in its struct's declaration, of
    /// the value of `type` that `pointer` points to, and returns the pointer with the field's type. Throws where
    /// `type` has no such field.
    private func fieldPointer(
        to field: Int, of type: RayoType, at pointer: PointerValue, with builder: borrowing Builder,
    ) throws(LLVMError) -> (PointerValue, RayoType) {
        // A field of a value that isn't a struct, or that its struct doesn't have, which the checker passes no IR
        // with, would point outside the value, so it fails here.
        guard case .structure(let id) = type, types.fields(of: id).indices.contains(field) else {
            throw LLVMError(message: "the IR reads field \(field) of a value of type \(types.llvmType(type).text)")
        }

        // Point at the element of the struct's LLVM type that holds the field.
        let (fieldType, element) = types.fields(of: id)[field]
        return (builder.fieldPointer(to: element, of: types.llvmStruct(id), at: pointer), fieldType)
    }

    /// Emits the instruction that stores `value` in `local`'s slot. Throws where `value` is of another type than
    /// `local`'s.
    private func store(_ value: AnyValue, in local: LocalID, with builder: borrowing Builder) throws(LLVMError) {
        // A value of another type, which the checker passes no IR with, would pass LLVM's verifier, since a slot is
        // a pointer of no type, and run as bits of the wrong type, so it fails here.
        let slotType = slotType(of: local)
        guard value.type == slotType else {
            let stored = "a value of type \(value.type.text)"
            throw LLVMError(message: "the IR stores \(stored) in a local of type \(slotType.text)")
        }
        builder.store(value, to: slots[local.index], alignment: alignment(of: local))
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
            try emit(rvalue, into: destination, at: range, in: program)

        // A declaration emits nothing: the program reads a slot only once a statement has stored to it.
        case .declare:
            break
        }
    }

    /// Emits the instructions that compute `rvalue`, and stores its result in `destination` when there is one.
    private func emit(
        _ rvalue: Rvalue, into destination: Place?, at range: SourceRange, in program: borrowing ProgramEmitter,
    ) throws(LLVMError) {
        let value = try compute(rvalue, at: range, in: program)

        // A value that no local takes is dropped.
        guard let destination else { return }
        // A call that returns nothing gives no value to store, and lowering stores none, so its store fails here.
        guard let value else { throw storeOfNothing(from: rvalue, in: destination.local) }
        try store(value, in: destination.local, with: program.builder)
    }

    /// The error that says the IR stores the result of `rvalue`, a call that returns nothing, in `local`.
    private func storeOfNothing(from rvalue: Rvalue, in local: LocalID) -> LLVMError {
        // Only a call gives no value.
        guard case .call(let callee, _) = rvalue else { preconditionFailure("only a call gives no value") }
        let result = "the result of '\(calledFunction(callee).name)', which returns nothing,"
        return LLVMError(message: "the IR stores \(result) in a local of type \(slotType(of: local).text)")
    }

    private func emit(_ terminator: Terminator, in program: borrowing ProgramEmitter) throws(LLVMError) {
        switch terminator {
        // A `goto` branches to the LLVM block made for its target.
        case .goto(let target):
            program.builder.branch(to: blocks[target.index])

        // A branch picks, on the condition's value, between the LLVM blocks made for its two targets.
        case .branch(let operand, let then, let otherwise):
            let value = try read(operand, in: program)
            // A condition that isn't a Bool, which the checker passes no IR with, fails here, saying what it is.
            guard let condition = IntValue<I1>(value) else {
                throw LLVMError(message: "the IR branches on a value of type \(value.type.text), where it takes i1")
            }
            program.builder.branch(if: condition, then: blocks[then.index], else: blocks[otherwise.index])

        // A `return` returns its operand's value, or nothing where it has none.
        case .return(let result):
            try emitReturn(result, in: program)

        // A block that no path reaches ends in LLVM's `unreachable`.
        case .unreachable:
            program.builder.unreachable()
        }
    }

    /// Emits the return of `result`'s value, or of nothing where there is no `result`. Throws where that isn't of
    /// the type the function returns.
    private func emitReturn(_ result: Operand?, in program: borrowing ProgramEmitter) throws(LLVMError) {
        let resultType = types.llvmType(function.result)

        // A `return` without an operand ends a function that returns nothing in `ret void`.
        guard let result else {
            // A function that returns a value, which the checker makes end in a `return` of it, fails here.
            guard function.result == .void else {
                throw LLVMError(message: "the IR returns nothing from a function that returns \(resultType.text)")
            }
            return program.builder.returnVoid()
        }

        // A value of another type than the function's result, which the checker passes no IR with, fails here.
        let value = try read(result, in: program)
        guard value.type == resultType else {
            let returned = "a value of type \(value.type.text)"
            throw LLVMError(message: "the IR returns \(returned) from a function that returns \(resultType.text)")
        }
        program.builder.return(value)
    }

    /// Emits the instructions that read `operand`'s value, and returns the value. Throws where it names a field that
    /// the value holding it doesn't have.
    private func read(_ operand: Operand, in program: borrowing ProgramEmitter) throws(LLVMError) -> AnyValue {
        switch operand {
        // An Int constant needs no instruction: it is an `i64` holding the Int's bits.
        case .constant(.int(let value)):
            types.int64.constant(value).anyValue

        // A Bool constant needs no instruction either: it is an `i1`, 1 for true and 0 for false.
        case .constant(.bool(let value)):
            types.bool.constant(value ? 1 : 0).anyValue

        // A read or a move loads the place from its slot; a move leaves the slot as it is, unread until assigned again.
        case .read(let place), .move(let place):
            try load(place, with: program.builder)
        }
    }

    /// Emits the instructions that compute `rvalue`, and returns the LLVM value holding its result, or nil
    /// when it has none.
    private func compute(
        _ rvalue: Rvalue, at range: SourceRange, in program: borrowing ProgramEmitter,
    ) throws(LLVMError) -> AnyValue? {
        switch rvalue {
        // A use is its operand's value.
        case .use(let operand):
            try read(operand, in: program)

        // An operator computes on its operands' values.
        case .unary(let op, let operand):
            try operators.emit(op, on: read(operand, in: program), at: range, in: program)
        case .binary(let op, let left, let right):
            try operators.emit(op, read(left, in: program), read(right, in: program), at: range, in: program)

        // A call passes its arguments' values.
        case .call(let callee, let arguments):
            try call(callee, passing: read(arguments, in: program), with: program.builder)

        // A struct's value is made of its fields' values.
        case .structure(let id, let fields):
            try structure(id, from: read(fields, in: program), with: program.builder)
        }
    }

    /// Emits the instructions that read each of `operands`, in order, and returns their values.
    private func read(_ operands: [Operand], in program: borrowing ProgramEmitter) throws(LLVMError) -> [AnyValue] {
        var values: [AnyValue] = []
        for operand in operands {
            values.append(try read(operand, in: program))
        }
        return values
    }

    /// Emits the instructions that make a value of the struct `id` from `fields`, the values of its fields in the order
    /// it declares them, and returns the value. Throws where `fields` aren't as many as the struct's, or of their
    /// types.
    private func structure(
        _ id: StructID, from fields: [AnyValue], with builder: borrowing Builder,
    ) throws(LLVMError) -> AnyValue {
        // LLVM stops the process on an `insertvalue` of the wrong type, where it checks its own invariants, so IR that
        // the checker passes no program with fails here.
        let declared = types.fields(of: id)
        // Values for more or fewer fields than the struct has fail.
        guard fields.count == declared.count else {
            let counts = "\(fields.count) fields, where it has \(declared.count)"
            throw LLVMError(message: "the IR makes '\(id.name)' of \(counts)")
        }

        // Insert each field's value into the element that holds the field, starting from a value of no particular bits.
        var value = types.llvmStruct(id).poison
        for (index, (field, declaredField)) in zip(fields, declared).enumerated() {
            // A value of another type than its field's fails.
            let fieldType = types.llvmType(declaredField.type)
            guard field.type == fieldType else {
                let given = "a value of type \(field.type.text), where it takes \(fieldType.text)"
                throw LLVMError(message: "the IR gives field \(index) of '\(id.name)' \(given)")
            }
            value = builder.insertValue(field, into: value, at: declaredField.element)
        }
        return value.anyValue
    }

    /// Emits a call of `callee` with `arguments`, and returns its result, or nil when it returns nothing. Throws where
    /// `arguments` aren't of the types `callee` takes.
    private func call(
        _ callee: Callee, passing arguments: [AnyValue], with builder: borrowing Builder,
    ) throws(LLVMError) -> AnyValue? {
        let function = calledFunction(callee)
        try check(arguments, of: function)
        return builder.call(function, arguments)
    }

    /// The LLVM function that `callee` names: the prelude's `print` is the runtime's.
    private func calledFunction(_ callee: Callee) -> Function {
        switch callee {
        case .printInt: runtime.printInt
        case .function(let id): functions[id.index]
        }
    }

    /// Throws where `arguments` aren't as many as `function` takes, or of the types it takes them as.
    private func check(_ arguments: [AnyValue], of function: Function) throws(LLVMError) {
        // LLVM stops the process on a call that doesn't match its function's type, where it checks its own
        // invariants, so a call the checker passes no IR with fails here.
        let parameters = function.type.parameters
        // A call passes as many arguments as the function has parameters.
        guard arguments.count == parameters.count else {
            let counts = "\(arguments.count) \(arguments.count == 1 ? "argument" : "arguments")"
            throw LLVMError(message: "the IR passes '\(function.name)' \(counts), where it takes \(parameters.count)")
        }

        // Each argument is of its parameter's type.
        for (argument, parameter) in zip(arguments, parameters) where argument.type != parameter {
            let passed = "an argument of type \(argument.type.text), where it takes \(parameter.text)"
            throw LLVMError(message: "the IR passes '\(function.name)' \(passed)")
        }
    }
}
