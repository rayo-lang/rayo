import LLVM
import RayoIR

/// Arrays, which an array operation builds in its destination one element at a time.
extension FunctionEmitter {
    /// Emits the loop that copies the value of `value` into each of the `count` elements of the array in
    /// `destination`. The loop is the same few instructions for an array of any count.
    func fill(
        _ destination: Place?, withCopiesOf value: Operand, count: Int, in program: borrowing ProgramEmitter,
    ) {
        let source = self.value(of: value, with: program.builder)

        // An array that no place takes is dropped, and finding its value changed nothing.
        guard let destination else { return }
        let array = address(of: destination, with: program.builder)

        // The loop counts the elements it has filled in a slot of its own, from 0.
        let filled = newSlot(of: .int, with: program.builder)
        store(types.int64.constant(0).anyValue, at: filled, with: program.builder)
        let header = program.context.appendBlock(named: "fill.header", to: llvmFunction)
        let body = program.context.appendBlock(named: "fill.body", to: llvmFunction)
        let end = program.context.appendBlock(named: "fill.end", to: llvmFunction)
        program.builder.branch(to: header)

        // The header goes on to the body while an element is left to fill, and past the loop once none is.
        program.builder.position(atEndOf: header)
        let index = int(whole(.place(filled), with: program.builder))
        let isFull = program.builder.compare(.unsignedGreaterEqual, index, types.int64.constant(Int64(count)))
        program.builder.branch(if: isFull, then: end, else: body)

        // The body copies the value into the element at the index, and counts it.
        program.builder.position(atEndOf: body)
        copy(source, to: elementAddress(at: index, in: array, with: program.builder), with: program.builder)
        store(program.builder.add(index, types.int64.constant(1)).anyValue, at: filled, with: program.builder)
        program.builder.branch(to: header)

        // The code after the array goes on once the loop has filled it.
        program.builder.position(atEndOf: end)
    }

    /// `value`, an index or a count, as LLVM holds an Int.
    private func int(_ value: AnyValue) -> IntValue<I64> {
        guard let int = IntValue<I64>(value) else { preconditionFailure("an Int is held as an i64") }
        return int
    }

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
