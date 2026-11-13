import LLVM
import RayoIR
import RayoSema

/// Calls, which pass their arguments and take their result as the called function's signature says.
extension FunctionEmitter {
    /// Emits a call of `callee` with `operands`, and stores its result in `destination` when there is one. Throws
    /// where the arguments aren't of the types `callee` takes, or the result isn't of the destination's.
    func call(
        _ callee: Callee, passing operands: [Operand], into destination: Place?, in program: borrowing ProgramEmitter,
    ) throws(LLVMError) {
        switch callee {
        case .builtin(let builtin):
            try call(builtin, passing: operands, into: destination, in: program)
        case .function(let id):
            try call(functions[id.index], passing: operands, into: destination, with: program.builder)
        }
    }

    /// Emits a call of `target` with `operands`, and stores its result in `destination` when there is one. Throws
    /// where the arguments aren't of the types `target` takes, or the result isn't of the destination's.
    func call(
        _ target: DeclaredFunction, passing operands: [Operand], into destination: Place?,
        with builder: borrowing Builder,
    ) throws(LLVMError) {
        let arguments = try values(of: operands, with: builder)
        try check(arguments, of: target)
        let destinationAddress = try destination.map { place throws(LLVMError) in
            try address(of: place, with: builder)
        }
        try checkResult(of: target, storedIn: destinationAddress)

        switch target.signature.result {
        case .direct:
            let result = try emitCall(of: target, passing: arguments, resultSlot: nil, with: builder)
            try storeResult(result, in: destinationAddress, with: builder)
        case .slot:
            try callWritingSlot(of: target, passing: arguments, from: operands, into: destination,
                                at: destinationAddress, with: builder)
        }
    }

    /// Emits a call of `target`, whose result is written to a slot, with `arguments`, the values of `operands`. The
    /// slot is `destination`'s place, at `address`, where nothing the call reads shares it, and otherwise a new one,
    /// copied into the destination after.
    private func callWritingSlot(
        of target: DeclaredFunction, passing arguments: [OperandValue], from operands: [Operand],
        into destination: Place?, at address: Address?, with builder: borrowing Builder,
    ) throws(LLVMError) {
        // A destination that no argument reads takes the result straight from the call.
        if let destination, let address, !anyOf(operands, overlaps: destination) {
            try emitCall(of: target, passing: arguments, resultSlot: address, with: builder)
            return
        }

        // Any other result is written to a new slot, since the call reads the arguments as it writes the result, and
        // copied into its destination, if any, once the call returns.
        let slot = newSlot(of: target.signature.source.result, with: builder)
        try emitCall(of: target, passing: arguments, resultSlot: slot, with: builder)
        guard let address else { return }
        try copy(.place(slot), to: address, with: builder)
    }

    /// Emits the call of `target` with `arguments`, writing its result to `resultSlot` where it is passed one, and
    /// returns the value the call returns, or nil where it returns nothing.
    @discardableResult
    private func emitCall(
        of target: DeclaredFunction, passing arguments: [OperandValue], resultSlot: Address?,
        with builder: borrowing Builder,
    ) throws(LLVMError) -> AnyValue? {
        // The result's slot comes ahead of the arguments, which each pass in their mode.
        var llvmArguments: [AnyValue] = resultSlot.map { [$0.pointer.anyValue] } ?? []
        for (argument, passing) in zip(arguments, target.signature.parameters) {
            llvmArguments += try pass(argument, as: passing, with: builder)
        }
        return builder.call(target.function, llvmArguments, parameterAttributes: target.signature.parameterAttributes)
    }

    /// Emits the instructions that pass `argument` as `passing` says, and returns the LLVM arguments that pass it.
    private func pass(
        _ argument: OperandValue, as passing: ParameterPassing, with builder: borrowing Builder,
    ) throws(LLVMError) -> [AnyValue] {
        switch passing {
        case .direct: try scalars(of: argument, with: builder)
        case .callerPlace: [placePointer(of: argument)]
        case .filledSlot: [try filledSlot(holding: argument, with: builder)]
        }
    }

    /// The pointer to the place that holds `argument`.
    private func placePointer(of argument: OperandValue) -> AnyValue {
        // A constant is an Int or a Bool, which passes directly to any parameter but a mutable one, and no mutable
        // parameter takes a constant.
        guard case .place(let address) = argument else {
            preconditionFailure("a constant is never passed in the caller's place")
        }
        return address.pointer.anyValue
    }

    /// Emits the copy of `argument` into a new slot, and returns the pointer to the slot.
    private func filledSlot(
        holding argument: OperandValue, with builder: borrowing Builder,
    ) throws(LLVMError) -> AnyValue {
        let slot = newSlot(of: argument.type, with: builder)
        try copy(argument, to: slot, with: builder)
        return slot.pointer.anyValue
    }

    /// Emits the stores of `result`, which a call returns directly, in the place at `destination`, where there is
    /// one.
    private func storeResult(
        _ result: AnyValue?, in destination: Address?, with builder: borrowing Builder,
    ) throws(LLVMError) {
        // A result that no place takes is dropped.
        guard let destination, let result else { return }

        // A result of one scalar returns it, and one of more returns them in a struct.
        guard let returnedStruct = AggregateValue(result) else {
            return try storeScalars([result], at: destination, with: builder)
        }
        let count = types.scalars(of: destination.type).count
        let scalars = (0..<count).map { builder.extractValue(from: returnedStruct, at: $0) }
        try storeScalars(scalars, at: destination, with: builder)
    }

    /// Throws where `arguments` aren't as many as `target` takes, or of the types it takes them as.
    private func check(_ arguments: [OperandValue], of target: DeclaredFunction) throws(LLVMError) {
        // LLVM stops the process on a call that doesn't match its function's type, where it checks its own
        // invariants, so a call the checker passes no IR with fails here.
        let name = target.function.name
        let parameters = target.signature.source.parameters
        // A call passes as many arguments as the function has parameters.
        guard arguments.count == parameters.count else {
            let counts = "\(arguments.count) \(arguments.count == 1 ? "argument" : "arguments")"
            throw LLVMError(message: "the IR passes '\(name)' \(counts), where it takes \(parameters.count)")
        }

        // Each argument is of its parameter's type.
        for (argument, parameter) in zip(arguments, parameters) where argument.type != parameter.type {
            let passed = "an argument of type \(types.llvmType(argument.type).text)"
            let taken = types.llvmType(parameter.type).text
            throw LLVMError(message: "the IR passes '\(name)' \(passed), where it takes \(taken)")
        }
    }

    /// Throws where a call of `target` stores its result in a place at `destination` of another type.
    private func checkResult(of target: DeclaredFunction, storedIn destination: Address?) throws(LLVMError) {
        // A result that no place takes is of any type.
        guard let destination else { return }
        let result = target.signature.source.result

        // A call that returns nothing gives no value to store, and lowering stores none.
        guard result != .void else {
            let returned = "the result of '\(target.function.name)', which returns nothing,"
            let place = "a place of type \(types.llvmType(destination.type).text)"
            throw LLVMError(message: "the IR stores \(returned) in \(place)")
        }
        // Nor does it store one of another type.
        guard result == destination.type else {
            throw mismatch(storing: types.llvmType(result), in: types.llvmType(destination.type))
        }
    }
}
