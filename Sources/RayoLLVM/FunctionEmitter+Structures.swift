import LLVM
import RayoCheckedProgram
import RayoIR

/// Structs, which a call of their primary initializer builds in its destination one field at a time.
extension FunctionEmitter {
    /// Emits the instructions that build a value of the struct `id` in `destination`, from `arguments`, the arguments
    /// of a call of its primary initializer, which pass the values of its fields in the order it declares them.
    func build(
        _ id: StructID, from arguments: [CallArgument], into destination: Place?, with builder: borrowing Builder,
    ) {
        let fields = arguments.map { value(of: $0, with: builder) }

        // A struct that no place takes is dropped, and reading its fields changed nothing.
        guard let destination else { return }

        // A struct is built in its destination, unless a field reads it, which a field written before would
        // change. Such a struct is built in a new slot, then copied in.
        let address = address(of: destination, with: builder)
        let readsDestination = anyOf(arguments, overlaps: destination)
        let target = readsDestination ? newTemporarySlot(of: address.type, with: builder) : address
        for (index, field) in fields.enumerated() {
            copy(field, to: fieldAddress(of: index, in: target, with: builder), with: builder)
        }

        // A struct built in a new slot is copied into its destination once every field is read, and the slot's life
        // ends.
        guard readsDestination else { return }
        copy(.place(target), to: address, with: builder)
        builder.endLife(of: target.pointer)
    }
}
