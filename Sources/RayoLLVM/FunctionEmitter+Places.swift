import LLVM
import RayoIR
import RayoSema

/// The places that hold a function's locals, and the reads, writes and copies of the values in them.
extension FunctionEmitter {
    /// Emits, in the entry block, the place of each local, and returns the pointers to them in the locals' order. A
    /// parameter's place holds its argument.
    func makePlaces(with builder: borrowing Builder) -> [PointerValue] {
        let returned = returnedLocal()
        var places: [PointerValue] = []
        for (index, local) in body.locals.enumerated() {
            let place = if index < declaration.parameters.count {
                parameterPlace(of: index, with: builder)
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
    private func parameterPlace(of index: Int, with builder: borrowing Builder) -> PointerValue {
        let llvmParameters = signature.llvmParameters(of: index)
        return switch signature.parameters[index] {
        // A value passed directly is put back together from its scalars, in a slot of its own.
        case .direct:
            slot(of: body.locals[index].type, holdingParameters: llvmParameters, with: builder).pointer
        // A value passed in a pointer lies where it points.
        case .callerPlace, .filledSlot:
            pointerParameter(at: llvmParameters.lowerBound)
        }
    }

    /// Emits a new slot for a value of `type`, and the stores in it of the scalars the LLVM parameters at
    /// `llvmParameters` pass, and returns its address.
    private func slot(
        of type: RayoType, holdingParameters llvmParameters: Range<Int>, with builder: borrowing Builder,
    ) -> Address {
        let slot = newSlot(of: type, with: builder)
        let scalars = llvmParameters.map { llvmFunction.parameter(at: $0) }
        storeScalars(scalars, at: slot, with: builder)
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
    func address(of place: Place, with builder: borrowing Builder) -> Address {
        let local = Address(pointer: places[place.root.index], type: body.locals[place.root.index].type)
        return address(following: place.steps, from: local, with: builder)
    }

    /// Emits the instructions that take each of `steps` in turn from the value at `address`, and returns the address
    /// of the last.
    private func address(
        following steps: [PlaceStep], from address: Address, with builder: borrowing Builder,
    ) -> Address {
        var address = address
        for step in steps {
            switch step {
            // A field lies inside the value that holds it.
            case .field(let field):
                address = fieldAddress(of: field, in: address, with: builder)

            // An element lies inside the array that holds it, at an index the IR writes or one a local holds.
            case .element(let index):
                address = elementAddress(of: index, in: address, with: builder)
            case .elementAt(let local):
                address = elementAddress(at: index(in: local, with: builder), in: address, with: builder)
            }
        }
        return address
    }

    /// Emits the load of the index that `local`, a UInt local, holds, and returns it.
    private func index(in local: LocalID, with builder: borrowing Builder) -> IntValue<I64> {
        let value = whole(.place(Address(pointer: places[local.index], type: .uint)), with: builder)
        // The verifier passes no IR that indexes by a local that isn't a UInt, which LLVM holds as an i64.
        guard let index = IntValue<I64>(value) else { preconditionFailure("a UInt is held as an i64") }
        return index
    }

    /// Emits the instructions that take each of `steps`, a scalar's, in turn from the value at `address`, and returns
    /// the scalar's address.
    private func address(
        following steps: [Scalar.Step], from address: Address, with builder: borrowing Builder,
    ) -> Address {
        var address = address
        for step in steps {
            switch step {
            // A field lies inside the struct that holds it.
            case .field(let field):
                address = fieldAddress(of: field, in: address, with: builder)

            // An element lies inside the array that holds it.
            case .element(let index):
                address = elementAddress(of: index, in: address, with: builder)
            }
        }
        return address
    }

    /// Emits the instruction that points at the field at `field`, its place in its struct's declaration, of the
    /// struct at `address`, and returns the field's address.
    func fieldAddress(of field: Int, in address: Address, with builder: borrowing Builder) -> Address {
        // Point at the element of the struct's LLVM type that holds the field. The verifier passes no IR that steps
        // into a field of a value that isn't a struct.
        let (fieldType, element) = types.fields(of: address.type)[field]
        let pointer = builder.fieldPointer(to: element, of: types.llvmStruct(address.type), at: address.pointer)
        return Address(pointer: pointer, type: fieldType)
    }

    /// Emits the instruction that points at the element at `index` of the array at `address`, and returns the
    /// element's address.
    func elementAddress(of index: Int, in address: Address, with builder: borrowing Builder) -> Address {
        elementAddress(at: types.int64.constant(Int64(index)), in: address, with: builder)
    }

    /// Emits the instruction that points at the element at `index`, a value the program computes, of the array at
    /// `address`, and returns the element's address.
    func elementAddress(at index: IntValue<I64>, in address: Address, with builder: borrowing Builder) -> Address {
        // Only an array has elements, which lie end to end from where it starts.
        guard case .array(_, let element) = address.type else { preconditionFailure("only an array has elements") }
        let pointer = builder.elementPointer(to: index, of: types.llvmType(element), at: address.pointer)
        return Address(pointer: pointer, type: element)
    }

    /// Emits the instructions that find the value `operand` gives, and returns it.
    func value(of operand: Operand, with builder: borrowing Builder) -> OperandValue {
        switch operand {
        // An Int constant is an `i64` holding the Int's bits.
        case .constant(.int(let value)):
            .constant(types.int64.constant(value).anyValue, .int)

        // A UInt constant is an `i64` holding the UInt's bits.
        case .constant(.uint(let value)):
            .constant(types.int64.constant(Int64(bitPattern: value)).anyValue, .uint)

        // A Bool constant is an `i1`, 1 for true and 0 for false.
        case .constant(.bool(let value)):
            .constant(types.bool.constant(value ? 1 : 0).anyValue, .bool)

        // A read or a move finds the place; a move leaves it as it is, unread until assigned again.
        case .read(let place, _), .move(let place, _):
            .place(address(of: place, with: builder))
        }
    }

    /// Emits the instructions that read `operand`'s value whole, and returns it.
    func read(_ operand: Operand, with builder: borrowing Builder) -> AnyValue {
        whole(value(of: operand, with: builder), with: builder)
    }

    /// Emits the load of `value` whole, where it lies in a place, and returns it.
    func whole(_ value: OperandValue, with builder: borrowing Builder) -> AnyValue {
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
    func scalars(of value: OperandValue, with builder: borrowing Builder) -> [AnyValue] {
        switch value {
        // A constant is an integer or a Bool, each one scalar.
        case .constant(let constant, _): [constant]
        // A value in a place is read one scalar at a time, from where each lies.
        case .place(let address): loadScalars(at: address, with: builder)
        }
    }

    /// Emits the loads of the scalars that the value at `address` splits into, and returns them in order.
    private func loadScalars(at address: Address, with builder: borrowing Builder) -> [AnyValue] {
        var loaded: [AnyValue] = []
        for scalar in types.scalars(of: address.type) {
            let scalarAddress = self.address(following: scalar.steps, from: address, with: builder)
            let (type, alignment) = (types.llvmType(scalar.type), types.alignment(of: scalar.type))
            loaded.append(builder.load(type, from: scalarAddress.pointer, alignment: alignment))
        }
        return loaded
    }

    /// Emits the stores of `scalars`, the scalars a value splits into, in order, in the place at `address`.
    func storeScalars(_ scalars: [AnyValue], at address: Address, with builder: borrowing Builder) {
        for (scalar, value) in zip(types.scalars(of: address.type), scalars) {
            let scalarAddress = self.address(following: scalar.steps, from: address, with: builder)
            builder.store(value, to: scalarAddress.pointer, alignment: types.alignment(of: scalar.type))
        }
    }

    /// Emits the copy of `value` into the place at `destination`, which holds a value of its type: whole where it is
    /// small, and with `memcpy` where it is large.
    func copy(_ value: OperandValue, to destination: Address, with builder: borrowing Builder) {
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

    /// Emits the instruction that stores `value`, a scalar of the type of the place at `address`, there.
    func store(_ value: AnyValue, at address: Address, with builder: borrowing Builder) {
        builder.store(value, to: address.pointer, alignment: types.alignment(of: address.type))
    }
}
