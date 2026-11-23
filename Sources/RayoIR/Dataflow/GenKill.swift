/// What a run of code, such as a block, does to a dataflow state's bits: it clears the bits in `kill`, then sets those
/// in `gen`. Worked out once, it takes a state across the whole run in a step for each 64 bits.
package struct GenKill: Equatable {
    package private(set) var gen: BitSet
    package private(set) var kill: BitSet

    /// A change of `count` bits that leaves each as it is.
    package init(count: Int) {
        gen = BitSet(count: count)
        kill = BitSet(count: count)
    }

    /// Follows the change with one that sets `bit` to `value`.
    package mutating func set(_ bit: Int, to value: Bool) {
        if value {
            gen.insert(bit)
        } else {
            // A later clear undoes an earlier set, whatever the bit held before.
            gen.remove(bit)
            kill.insert(bit)
        }
    }

    package func apply(to bits: inout BitSet) {
        bits.subtract(kill)
        bits.formUnion(gen)
    }
}
