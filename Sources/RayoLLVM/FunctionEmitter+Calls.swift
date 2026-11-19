import LLVM
import RayoCheckedProgram
import RayoIR
import RayoSource

/// Calls, which pass their arguments and take their result as the called function's signature says.
extension FunctionEmitter {
    /// Emits a call of `callee` with `arguments`, which the source makes at `range`, and stores its result in
    /// `destination` when there is one.
    func call(
        _ callee: Callee, passing arguments: [CallArgument], into destination: Place?, at range: SourceRange,
        in program: borrowing ProgramEmitter,
    ) {
        switch callee {
        case .builtin(let builtin):
            call(builtin, passing: arguments, into: destination, at: range, in: program)
        case .function(let id):
            call(callTargets[id.index], passing: arguments, into: destination, with: program.builder)
        }
    }

    /// Emits a call that reaches `target` with `arguments`, and stores its result in `destination` when there is
    /// one.
    private func call(
        _ target: CallTarget, passing arguments: [CallArgument], into destination: Place?,
        with builder: borrowing Builder,
    ) {
        switch target {
        case .function(let function):
            call(function, passing: arguments, into: destination, with: builder)
        case .primaryInitializer(let id):
            build(id, from: arguments, into: destination, with: builder)
        }
    }

    /// Emits a call of `function` with `arguments`, of the types it takes, and stores its result in `destination`, a
    /// place of the result's type, when there is one.
    func call(
        _ function: DeclaredFunction, passing arguments: [CallArgument], into destination: Place?,
        with builder: borrowing Builder,
    ) {
        let values = arguments.map { value(of: $0, with: builder) }
        let destinationAddress = destination.map { address(of: $0, with: builder) }

        switch function.signature.result {
        case .direct:
            let result = emitCall(of: function, passing: values, resultSlot: nil, with: builder)
            storeResult(result, in: destinationAddress, with: builder)
        case .slot:
            callWritingSlot(of: function, passing: values, from: arguments, into: destination,
                            at: destinationAddress, with: builder)
        }
    }

    /// The value `argument` passes: its operand's, or the place its access reaches.
    func value(of argument: CallArgument, with builder: borrowing Builder) -> OperandValue {
        switch argument {
        case .operand(let operand): value(of: operand, with: builder)
        case .access(let id): .place(begun(id).address)
        }
    }

    /// Whether any of `arguments` reads, moves or reaches a place that shares memory with `destination`, which a
    /// write to `destination` before the arguments are read would change.
    func anyOf(_ arguments: [CallArgument], overlaps destination: Place) -> Bool {
        arguments.contains { argument in
            let place = switch argument {
            case .operand(let operand): operand.place
            case .access(let id): begun(id).place as Place?
            }
            return place?.mayOverlap(destination) ?? false
        }
    }

    /// The access `id`, which every path to its use has begun.
    private func begun(_ id: AccessID) -> BegunAccess {
        guard let access = accesses[id] else { preconditionFailure("a\(id.index) is used before it begins") }
        return access
    }

    /// Emits a call of `target`, whose result is written to a slot, with `arguments`, the values that
    /// `callArguments` pass. The slot is `destination`'s place, at `address`, where nothing the call reads shares it,
    /// and otherwise a new one, copied into the destination after.
    private func callWritingSlot(
        of target: DeclaredFunction, passing arguments: [OperandValue], from callArguments: [CallArgument],
        into destination: Place?, at address: Address?, with builder: borrowing Builder,
    ) {
        // A destination that no argument reads takes the result straight from the call.
        if let destination, let address, !anyOf(callArguments, overlaps: destination) {
            emitCall(of: target, passing: arguments, resultSlot: address, with: builder)
            return
        }

        // Any other result is written to a new slot, since the call reads the arguments as it writes the result, and
        // copied into its destination, if any, once the call returns.
        let slot = newTemporarySlot(of: target.signature.resultType, with: builder)
        emitCall(of: target, passing: arguments, resultSlot: slot, with: builder)
        if let address { copy(.place(slot), to: address, with: builder) }
        builder.endLife(of: slot.pointer)
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
        var filledSlots: [PointerValue] = []
        for (argument, passing) in zip(arguments, target.signature.parameters) {
            let passed = pass(argument, as: passing, with: builder)
            llvmArguments += passed.arguments
            if let slot = passed.filledSlot { filledSlots.append(slot) }
        }
        let result = builder.call(target.function, llvmArguments,
                                  parameterAttributes: target.signature.parameterAttributes)

        // A slot the caller fills is the callee's for the call alone, so its life ends once the call returns.
        for slot in filledSlots {
            builder.endLife(of: slot)
        }
        return result
    }

    /// Emits the instructions that pass `argument` as `passing` says, and returns the LLVM arguments that pass it, and
    /// the slot it fills to pass the argument, where it fills one.
    private func pass(
        _ argument: OperandValue, as passing: ParameterPassing, with builder: borrowing Builder,
    ) -> (arguments: [AnyValue], filledSlot: PointerValue?) {
        switch passing {
        case .direct:
            (scalars(of: argument, with: builder), nil)
        case .callerPlace:
            ([placePointer(of: argument)], nil)
        case .filledSlot:
            filledSlot(holding: argument, with: builder)
        }
    }

    /// The pointer to the place that holds `argument`.
    private func placePointer(of argument: OperandValue) -> AnyValue {
        // A constant is an integer or a Bool, which passes directly to any parameter but a mutable one, and no mutable
        // parameter takes a constant.
        guard case .place(let address) = argument else {
            preconditionFailure("a constant is never passed in the caller's place")
        }
        return address.pointer.anyValue
    }

    /// Emits the copy of `argument` into a new slot, whose life starts here, and returns the LLVM argument that passes
    /// it, the pointer to the slot, and the slot.
    private func filledSlot(
        holding argument: OperandValue, with builder: borrowing Builder,
    ) -> (arguments: [AnyValue], filledSlot: PointerValue?) {
        let slot = newTemporarySlot(of: argument.type, with: builder)
        copy(argument, to: slot, with: builder)
        return ([slot.pointer.anyValue], slot.pointer)
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
        let count = types.scalarCount(of: destination.type)
        let scalars = (0..<count).map { builder.extractValue(from: returnedStruct, at: $0) }
        storeScalars(scalars, at: destination, with: builder)
    }
}
