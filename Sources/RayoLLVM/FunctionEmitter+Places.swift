import LLVM
import RayoIR
import RayoSema

/// The places that hold a function's locals, and the reads, writes and copies of the values in them.
extension FunctionEmitter {
    /// Emits, in the entry block, the place of each local, and returns the pointers to them in the locals' order. A
    /// parameter's place holds its argument.
    func makePlaces(with builder: borrowing Builder) throws(LLVMError) -> [PointerValue] {
        let returned = returnedLocal()
        var places: [PointerValue] = []
        for (index, local) in function.locals.enumerated() {
            let place = if index < function.parameterCount {
                try parameterPlace(of: index, with: builder)
            } else if LocalID(index: index) == returned {
                pointerParameter(at: 0)
            } else {
                newSlot(of: local.type, with: builder).pointer
            }
            places.append(place)
        }
        return places
    }

    /// Emits the place of the parameter at `index`: the memory its pointer points to where it is passed one, and
    /// otherwise a slot that its scalars are stored in.
    private func parameterPlace(of index: Int, with builder: borrowing Builder) throws(LLVMError) -> PointerValue {
        let llvmParameters = signature.llvmParameters(of: index)
        return switch signature.parameters[index] {
        // A value passed directly is put back together from its scalars, in a slot of its own.
        case .direct:
            try slot(of: function.locals[index].type, holdingParameters: llvmParameters, with: builder).pointer
        // A value passed in a pointer lies where it points.
        case .callerPlace, .filledSlot:
            pointerParameter(at: llvmParameters.lowerBound)
        }
    }

    /// Emits a new slot for a value of `type`, and the stores in it of the scalars the LLVM parameters at
    /// `llvmParameters` pass, and returns its address.
    private func slot(
        of type: RayoType, holdingParameters llvmParameters: Range<Int>, with builder: borrowing Builder,
    ) throws(LLVMError) -> Address {
        let slot = newSlot(of: type, with: builder)
        let scalars = llvmParameters.map { llvmFunction.parameter(at: $0) }
        try storeScalars(scalars, at: slot, with: builder)
        return slot
    }

    /// The function's LLVM parameter at `index`, which the function's signature makes a pointer.
    func pointerParameter(at index: Int) -> PointerValue {
        guard let pointer = PointerValue(llvmFunction.parameter(at: index)) else {
            preconditionFailure("the signature passes a pointer in LLVM parameter \(index)")
        }
        return pointer
    }

    /// Emits, in the entry block, a stack slot for a value of `type`, and returns its address. The builder stays where
    /// it was.
    func newSlot(of type: RayoType, with builder: borrowing Builder) -> Address {
        // A slot in the entry block is allocated once, however often a loop runs the code that uses it.
        let current = builder.insertionBlock
        builder.position(atEndOf: entry)
        let slot = builder.allocate(types.llvmType(type), alignment: types.alignment(of: type))
        builder.position(atEndOf: current)
        return Address(pointer: slot, type: type)
    }

    /// Emits the instructions that point at `place`, a local's place or a part inside it, and returns its address.
    /// Throws where the place names a field that the value holding it doesn't have.
    func address(of place: Place, with builder: borrowing Builder) throws(LLVMError) -> Address {
        let local = Address(pointer: places[place.root.index], type: function.locals[place.root.index].type)
        return try address(following: place.steps, from: local, with: builder)
    }

    /// Emits the instructions that take each of `steps` in turn from the value at `address`, and returns the address
    /// of the last.
    private func address(
        following steps: [PlaceStep], from address: Address, with builder: borrowing Builder,
    ) throws(LLVMError) -> Address {
        var address = address
        for step in steps {
            switch step {
            // A field lies inside the value that holds it.
            case .field(let field):
                address = try fieldAddress(of: field, in: address, with: builder)
            }
        }
        return address
    }

    /// Emits the instruction that points at the field at `field`, its place in its struct's declaration, of the
    /// value at `address`, and returns the field's address. Throws where the value has no such field.
    func fieldAddress(
        of field: Int, in address: Address, with builder: borrowing Builder,
    ) throws(LLVMError) -> Address {
        // A field of a value that isn't a struct, or that its struct doesn't have, which the checker passes no IR
        // with, would point outside the value, so each fails here.
        guard case .structure(let id) = address.type else { throw noField(field, of: address.type) }
        let fields = types.fields(of: id)
        guard fields.indices.contains(field) else { throw noField(field, of: address.type) }

        // Point at the element of the struct's LLVM type that holds the field.
        let (fieldType, element) = fields[field]
        let pointer = builder.fieldPointer(to: element, of: types.llvmStruct(id), at: address.pointer)
        return Address(pointer: pointer, type: fieldType)
    }

    /// The error that says the IR names the field at `field` of a value of `type`, which has no such field.
    private func noField(_ field: Int, of type: RayoType) -> LLVMError {
        LLVMError(message: "the IR names field \(field) of a value of type \(types.llvmType(type).text)")
    }

    /// Emits the instructions that find the value `operand` gives, and returns it. Throws where it names a field that
    /// the value holding it doesn't have.
    func value(of operand: Operand, with builder: borrowing Builder) throws(LLVMError) -> OperandValue {
        switch operand {
        // An Int constant is an `i64` holding the Int's bits.
        case .constant(.int(let value)):
            .constant(types.int64.constant(value).anyValue, .int)

        // A Bool constant is an `i1`, 1 for true and 0 for false.
        case .constant(.bool(let value)):
            .constant(types.bool.constant(value ? 1 : 0).anyValue, .bool)

        // A read or a move finds the place; a move leaves it as it is, unread until assigned again.
        case .read(let place, _), .move(let place, _):
            .place(try address(of: place, with: builder))
        }
    }

    /// Emits the instructions that find each of `operands`' values, in order, and returns them.
    func values(of operands: [Operand], with builder: borrowing Builder) throws(LLVMError) -> [OperandValue] {
        var values: [OperandValue] = []
        for operand in operands {
            values.append(try value(of: operand, with: builder))
        }
        return values
    }

    /// Emits the instructions that read `operand`'s value whole, and returns it.
    func read(_ operand: Operand, with builder: borrowing Builder) throws(LLVMError) -> AnyValue {
        whole(try value(of: operand, with: builder), with: builder)
    }

    /// Emits the load of `value` whole, where it lies in a place, and returns it.
    private func whole(_ value: OperandValue, with builder: borrowing Builder) -> AnyValue {
        switch value {
        // A constant is held whole already.
        case .constant(let constant, _):
            constant

        // A value lies in memory aligned as its type is, a field too, since its struct's layout keeps it so.
        case .place(let address):
            builder.load(types.llvmType(address.type), from: address.pointer,
                         alignment: types.alignment(of: address.type))
        }
    }

    /// Emits the loads of the scalars `value` splits into, and returns them in order.
    func scalars(of value: OperandValue, with builder: borrowing Builder) throws(LLVMError) -> [AnyValue] {
        switch value {
        // A constant is an Int or a Bool, each one scalar.
        case .constant(let constant, _): [constant]
        // A value in a place is read one scalar at a time, from where each lies.
        case .place(let address): try loadScalars(at: address, with: builder)
        }
    }

    /// Emits the loads of the scalars that the value at `address` splits into, and returns them in order.
    private func loadScalars(at address: Address, with builder: borrowing Builder) throws(LLVMError) -> [AnyValue] {
        var loaded: [AnyValue] = []
        for scalar in types.scalars(of: address.type) {
            let scalarAddress = try self.address(following: scalar.steps, from: address, with: builder)
            let (type, alignment) = (types.llvmType(scalar.type), types.alignment(of: scalar.type))
            loaded.append(builder.load(type, from: scalarAddress.pointer, alignment: alignment))
        }
        return loaded
    }

    /// Emits the stores of `scalars`, the scalars a value splits into, in order, in the place at `address`.
    func storeScalars(_ scalars: [AnyValue], at address: Address, with builder: borrowing Builder) throws(LLVMError) {
        for (scalar, value) in zip(types.scalars(of: address.type), scalars) {
            let scalarAddress = try self.address(following: scalar.steps, from: address, with: builder)
            builder.store(value, to: scalarAddress.pointer, alignment: types.alignment(of: scalar.type))
        }
    }

    /// Emits the copy of `value` into the place at `destination`: whole where it is small, and with `memcpy` where
    /// it is large. Throws where `value` is of another type than the place's.
    func copy(_ value: OperandValue, to destination: Address, with builder: borrowing Builder) throws(LLVMError) {
        // A value of another type, which the checker passes no IR with, would run as bits of the wrong type.
        guard value.type == destination.type else {
            throw mismatch(storing: types.llvmType(value.type), in: types.llvmType(destination.type))
        }

        switch value {
        // A large value in a place is copied byte for byte, never loaded whole.
        case .place(let source) where !lowering.isSmall(source.type):
            let layout = types.layout(of: source.type)
            builder.copyMemory(to: destination.pointer, from: source.pointer, size: layout.size,
                               alignment: layout.alignment)

        // A small one is loaded and stored whole.
        default:
            builder.store(whole(value, with: builder), to: destination.pointer,
                          alignment: types.alignment(of: destination.type))
        }
    }

    /// Emits the instruction that stores `value`, a scalar, at `address`. Throws where `value` is of another type
    /// than the place's.
    func store(_ value: AnyValue, at address: Address, with builder: borrowing Builder) throws(LLVMError) {
        // A value of another type, which the checker passes no IR with, would pass LLVM's verifier, since a pointer
        // has no type, and run as bits of the wrong type, so it fails here.
        let placeType = types.llvmType(address.type)
        guard value.type == placeType else { throw mismatch(storing: value.type, in: placeType) }
        builder.store(value, to: address.pointer, alignment: types.alignment(of: address.type))
    }

    /// The error that says the IR stores a value of `stored` in a place of `place`.
    func mismatch(storing stored: AnyType, in place: AnyType) -> LLVMError {
        LLVMError(message: "the IR stores a value of type \(stored.text) in a place of type \(place.text)")
    }

    /// Whether any of `operands` reads or moves a place that shares memory with `destination`, which a write to
    /// `destination` before the operands are read would change.
    func anyOf(_ operands: [Operand], overlaps destination: Place) -> Bool {
        operands.contains { $0.place?.overlaps(destination) ?? false }
    }
}

private extension Place {
    /// Whether this place and `other` share memory: whether one lies inside the other.
    func overlaps(_ other: Place) -> Bool {
        contains(other) || other.contains(self)
    }
}

private extension Operand {
    /// The place the operand reads or moves, or nil for a constant.
    var place: Place? {
        switch self {
        case .read(let place, _), .move(let place, _): place
        case .constant: nil
        }
    }
}
