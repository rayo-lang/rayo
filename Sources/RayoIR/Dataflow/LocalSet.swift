import RayoCheckedProgram

/// A set of a function's locals, for the state of a dataflow analysis. Blocks change few locals, so the copies a walk
/// through a function makes share the rest, and merging and comparing them cost only what differs between them.
package struct LocalSet: Equatable {
    /// A bit for each local, indexed by `LocalID`, set where the set holds it.
    private var words: PersistentArray<UInt64>

    /// The set of none of the locals of a function that numbers its locals below `localCount`.
    package init(localCount: Int) {
        let wordCount = (localCount + UInt64.bitWidth - 1) / UInt64.bitWidth
        words = PersistentArray(Array(repeating: 0, count: wordCount))
    }

    package func contains(_ local: LocalID) -> Bool {
        words[Self.word(of: local)] & Self.bit(of: local) != 0
    }

    package mutating func insert(_ local: LocalID) {
        let index = Self.word(of: local)
        let word = words[index]
        // A local already in the set leaves it as it is, without the second walk down the array a write takes.
        guard word & Self.bit(of: local) == 0 else { return }
        words[index] = word | Self.bit(of: local)
    }

    package mutating func remove(_ local: LocalID) {
        let index = Self.word(of: local)
        let word = words[index]
        // A local not in the set leaves it as it is, without the second walk down the array a write takes.
        guard word & Self.bit(of: local) != 0 else { return }
        words[index] = word & ~Self.bit(of: local)
    }

    /// The locals that this set or `other`, a set of the same function's locals, holds.
    package func union(_ other: LocalSet) -> LocalSet {
        var union = self
        union.words = words.merged(with: other.words) { $0 | $1 }
        return union
    }

    /// The locals that this set holds and `other`, a set of the same function's locals, leaves out, in the order of
    /// their IDs.
    package func locals(notIn other: LocalSet) -> [LocalID] {
        var locals: [LocalID] = []
        for word in words.indices(differingFrom: other.words) {
            // Each bit left in the word stands for one local, lowest first.
            var bits = words[word] & ~other.words[word]
            while bits != 0 {
                locals.append(LocalID(index: word * UInt64.bitWidth + bits.trailingZeroBitCount))
                bits &= bits - 1
            }
        }
        return locals
    }

    private static func word(of local: LocalID) -> Int {
        local.index / UInt64.bitWidth
    }

    private static func bit(of local: LocalID) -> UInt64 {
        1 << UInt64(local.index % UInt64.bitWidth)
    }
}
