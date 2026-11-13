import LLVM
import RayoIR
import RayoSema

/// Returns, which give the function's result back as its signature says.
extension FunctionEmitter {
    /// Emits the return of `result`'s value, a value of the type the function returns, or of nothing where there is
    /// no `result`, which the function then returns.
    func emitReturn(_ result: Operand?, with builder: borrowing Builder) {
        // A `return` without an operand ends a function that returns nothing in `ret void`.
        guard let result else { return builder.returnVoid() }

        let value = value(of: result, with: builder)
        switch signature.result {
        // A result passed directly returns its scalars.
        case .direct:
            returnDirectly(value, with: builder)
        // One written to a slot is copied there.
        case .slot:
            returnInSlot(value, with: builder)
        }
    }

    /// Emits the return of `value`'s scalars: of nothing where it has none, of its one scalar, or of a struct of
    /// them all.
    private func returnDirectly(_ value: OperandValue, with builder: borrowing Builder) {
        let scalars = scalars(of: value, with: builder)

        // A value of more than one scalar returns them in the signature's struct.
        if let returnedStruct = signature.returnedStruct {
            var aggregate = returnedStruct.poison
            for (index, scalar) in scalars.enumerated() {
                aggregate = builder.insertValue(scalar, into: aggregate, at: index)
            }
            return builder.return(aggregate)
        }
        // One of one scalar returns it.
        if let scalar = scalars.first { return builder.return(scalar) }
        // One of none returns nothing.
        builder.returnVoid()
    }

    /// Emits the copy of `value` into the slot the caller passes for the result, unless it lies there already, and
    /// the return of nothing.
    private func returnInSlot(_ value: OperandValue, with builder: borrowing Builder) {
        // The slot is the first LLVM parameter, ahead of the arguments.
        let slot = Address(pointer: pointerParameter(at: 0), type: declaration.result)
        // A value built in the slot is there already.
        if case .place(let address) = value, address.pointer == slot.pointer { return builder.returnVoid() }

        copy(value, to: slot, with: builder)
        builder.returnVoid()
    }

    /// The local that every `return` returns whole, whose place is then the caller's result slot, so the value
    /// is built where the caller takes it. Nil where the result isn't written to a slot, or the returns return
    /// different values.
    func returnedLocal() -> LocalID? {
        // A result returned directly has no slot to build it in.
        guard case .slot = signature.result else { return nil }

        // Gather what each `return` gives the whole of: a local, or nil for anything else.
        var returned: Set<LocalID?> = []
        for block in body.blocks {
            if case .return(let operand) = block.terminator { returned.insert(operand.flatMap(Self.wholeLocal)) }
        }

        // Every `return` must give the whole of one local of the result's type, which isn't a parameter, whose
        // place is the caller's.
        guard returned.count == 1, let local = returned.first ?? nil else { return nil }
        let isResult = body.locals[local.index].type == declaration.result
        return local.index >= declaration.parameters.count && isResult ? local : nil
    }

    /// The local `operand` reads or moves the whole of, or nil where it is a constant or a field.
    private static func wholeLocal(of operand: Operand) -> LocalID? {
        switch operand {
        case .read(let place, _), .move(let place, _): place.steps.isEmpty ? place.root : nil
        case .constant: nil
        }
    }
}
