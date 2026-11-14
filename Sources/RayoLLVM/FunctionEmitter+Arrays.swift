import LLVM
import RayoIR

/// Arrays, which an array operation builds in its destination one element at a time.
extension FunctionEmitter {
    /// Emits the instructions that build an array of the values of `elements`, in order, in `destination`.
    func build(arrayOf elements: [Operand], into destination: Place?, with builder: borrowing Builder) {
        let values = elements.map { value(of: $0, with: builder) }

        // An array that no place takes is dropped, and finding its elements changed nothing.
        guard let destination else { return }

        // An array is built in its destination, unless an element reads it, which an element written before would
        // change. Such an array is built in a new slot, then copied in.
        let address = address(of: destination, with: builder)
        let readsDestination = elements.contains { $0.place?.overlaps(destination) ?? false }
        let target = readsDestination ? newSlot(of: address.type, with: builder) : address
        for (index, value) in values.enumerated() {
            copy(value, to: elementAddress(of: index, in: target, with: builder), with: builder)
        }

        // An array built in a new slot is copied into its destination once every element is read.
        if readsDestination { copy(.place(target), to: address, with: builder) }
    }
}
