import LLVM
import RayoIR
import RayoSema

/// Structs, which are built in their place one field at a time.
extension FunctionEmitter {
    /// Emits the instructions that build a value of the struct `id` in `destination`, from `operands`, the values of
    /// its fields in the order it declares them. Throws where they aren't as many as the struct's fields, or of their
    /// types.
    func build(
        _ id: StructID, from operands: [Operand], into destination: Place?, with builder: borrowing Builder,
    ) throws(LLVMError) {
        let fields = try values(of: operands, with: builder)
        try check(fields, of: id)

        // A struct that no place takes is dropped, and reading its fields changed nothing.
        guard let destination else { return }

        // A struct is built in its destination, unless a field reads it, which a field written before would
        // change. Such a struct is built in a new slot, then copied in.
        let address = try address(of: destination, with: builder)
        let readsDestination = anyOf(operands, overlaps: destination)
        let target = readsDestination ? newSlot(of: address.type, with: builder) : address
        for (index, field) in fields.enumerated() {
            try copy(field, to: fieldAddress(of: index, in: target, with: builder), with: builder)
        }
        if readsDestination { try copy(.place(target), to: address, with: builder) }
    }

    /// Throws where `fields` aren't as many as the struct `id`'s, or of their types.
    private func check(_ fields: [OperandValue], of id: StructID) throws(LLVMError) {
        // Values for more or fewer fields than the struct has fail.
        let declared = types.fields(of: id)
        guard fields.count == declared.count else {
            let counts = "\(fields.count) fields, where it has \(declared.count)"
            throw LLVMError(message: "the IR makes '\(id.name)' of \(counts)")
        }

        // A value of another type than its field's fails.
        for (index, (field, declaredField)) in zip(fields, declared).enumerated()
        where field.type != declaredField.type {
            let given = "a value of type \(types.llvmType(field.type).text)"
            let taken = types.llvmType(declaredField.type).text
            throw LLVMError(message: "the IR gives field \(index) of '\(id.name)' \(given), where it takes \(taken)")
        }
    }
}
