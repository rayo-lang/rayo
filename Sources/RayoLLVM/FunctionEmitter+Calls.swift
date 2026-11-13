import LLVM
import RayoIR
import RayoSema

/// Calls, which pass their arguments and take their result as the called function's signature says.
extension FunctionEmitter {
    /// Emits a call of `callee` with `operands`, and stores its result in `destination` when there is one. Throws
    /// where the runtime lacks the function that a built-in calls.
    func call(
        _ callee: Callee, passing operands: [Operand], into destination: Place?, in program: borrowing ProgramEmitter,
    ) throws(LLVMError) {
        switch callee {
        case .builtin(let builtin):
            try call(builtin, passing: operands, into: destination, in: program)
        case .function(let id):
            call(functions[id.index], passing: operands, into: destination, with: program.builder)
        }
    }

    /// Emits a call of `target` with `operands`, of the types it takes, and stores its result in `destination`, a
    /// place of the result's type, when there is one.
    func call(
        _ target: DeclaredFunction, passing operands: [Operand], into destination: Place?,
        with builder: borrowing Builder,
    ) {
        let arguments = values(of: operands, with: builder)
        let destinationAddress = destination.map { address(of: $0, with: builder) }

        switch target.signature.result {
        case .direct:
            let result = emitCall(of: target, passing: arguments, resultSlot: nil, with: builder)
            storeResult(result, in: destinationAddress, with: builder)
        case .slot:
            callWritingSlot(of: target, passing: arguments, from: operands, into: destination,
                                at: destinationAddress, with: builder)
        }
    }

    /// Emits a call of `target`, whose result is written to a slot, with `arguments`, the values of `operands`. The
    /// slot is `destination`'s place, at `address`, where nothing the call reads shares it, and otherwise a new one,
    /// copied into the destination after.
    private func callWritingSlot(
        of target: DeclaredFunction, passing arguments: [OperandValue], from operands: [Operand],
        into destination: Place?, at address: Address?, with builder: borrowing Builder,
    ) {
        // A destination that no argument reads takes the result straight from the call.
        if let destination, let address, !anyOf(operands, overlaps: destination) {
            emitCall(of: target, passing: arguments, resultSlot: address, with: builder)
            return
        }

        // Any other result is written to a new slot, since the call reads the arguments as it writes the result, and
        // copied into its destination, if any, once the call returns.
        let slot = newSlot(of: target.signature.source.result, with: builder)
        emitCall(of: target, passing: arguments, resultSlot: slot, with: builder)
        guard let address else { return }
        copy(.place(slot), to: address, with: builder)
    }

    /// Emits the call of `target` with `arguments`, writing its result to `resultSlot` where it is passed one, and
    /// returns the value the call returns, or nil where it returns nothing.
    @discardableResult
    private func emitCall(
        of target: DeclaredFunction, passing arguments: [OperandValue], resultSlot: Address?,
        with builder: borrowing Builder,
    ) -> AnyValue? {
        // The result's slot comes ahead of the arguments, which each pass in their mode.
        var llvmArguments: [AnyValue] = resultSlot.map { [$0.pointer.anyValue] } ?? []
        for (argument, passing) in zip(arguments, target.signature.parameters) {
            llvmArguments += pass(argument, as: passing, with: builder)
        }
        return builder.call(target.function, llvmArguments, parameterAttributes: target.signature.parameterAttributes)
    }

    /// Emits the instructions that pass `argument` as `passing` says, and returns the LLVM arguments that pass it.
    private func pass(
        _ argument: OperandValue, as passing: ParameterPassing, with builder: borrowing Builder,
    ) -> [AnyValue] {
        switch passing {
        case .direct: scalars(of: argument, with: builder)
        case .callerPlace: [placePointer(of: argument)]
        case .filledSlot: [filledSlot(holding: argument, with: builder)]
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
    private func filledSlot(holding argument: OperandValue, with builder: borrowing Builder) -> AnyValue {
        let slot = newSlot(of: argument.type, with: builder)
        copy(argument, to: slot, with: builder)
        return slot.pointer.anyValue
    }

    /// Emits the stores of `result`, which a call returns directly, in the place at `destination`, where there is
    /// one.
    private func storeResult(_ result: AnyValue?, in destination: Address?, with builder: borrowing Builder) {
        // A result that no place takes is dropped.
        guard let destination, let result else { return }

        // A result of one scalar returns it, and one of more returns them in a struct.
        guard let returnedStruct = AggregateValue(result) else {
            return storeScalars([result], at: destination, with: builder)
        }
        let count = types.scalars(of: destination.type).count
        let scalars = (0..<count).map { builder.extractValue(from: returnedStruct, at: $0) }
        storeScalars(scalars, at: destination, with: builder)
    }
}
