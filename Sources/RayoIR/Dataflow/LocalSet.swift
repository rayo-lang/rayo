import RayoCheckedProgram

/// A set of a function's locals, for the state of a dataflow analysis, as a bit for each local. A set of many locals
/// keeps its bits in a persistent array, so the copies a walk through a function makes share the words none of them
/// changed, and merging and comparing them cost only what differs between them.
package struct LocalSet: Equatable {
    /// The bits of a set of few locals, indexed by `LocalID`, each set where the set holds its local; empty in a set of
    /// many.
    private var fewWords: [UInt64]
    /// The bits of a set of many locals, indexed the same way; empty in a set of few.
    private var manyWords: PersistentArray<UInt64>

    /// The most words a set keeps in one array: about as much memory as the two nodes that a persistent array copies
    /// for a change, so copying them whole costs no more than sharing them would.
    private static let fewWordLimit = 64

    /// The set of none of the locals of a function that numbers its locals below `localCount`.
    package init(localCount: Int) {
        let words = Array(repeating: UInt64(0), count: (localCount + UInt64.bitWidth - 1) / UInt64.bitWidth)
        let isFew = words.count <= Self.fewWordLimit
        fewWords = isFew ? words : []
        manyWords = PersistentArray(isFew ? [] : words)
    }

    package func contains(_ local: LocalID) -> Bool {
        word(at: Self.word(of: local)) & Self.bit(of: local) != 0
    }

    package mutating func insert(_ local: LocalID) {
        let index = Self.word(of: local)
        let word = word(at: index)
        // A local already in the set leaves it as it is, without the second walk down the array a write takes.
        guard word & Self.bit(of: local) == 0 else { return }
        setWord(word | Self.bit(of: local), at: index)
    }

    package mutating func remove(_ local: LocalID) {
        let index = Self.word(of: local)
        let word = word(at: index)
        // A local not in the set leaves it as it is, without the second walk down the array a write takes.
        guard word & Self.bit(of: local) != 0 else { return }
        setWord(word & ~Self.bit(of: local), at: index)
    }

    /// The locals that this set or `other`, a set of the same function's locals, holds.
    package func union(_ other: LocalSet) -> LocalSet {
        var union = self
        guard !fewWords.isEmpty else {
            union.manyWords = manyWords.merged(with: other.manyWords) { $0 | $1 }
            return union
        }

        // Only a word that `other` adds to is written, so a union that adds nothing shares this set's array.
        for index in fewWords.indices where other.fewWords[index] & ~fewWords[index] != 0 {
            union.fewWords[index] |= other.fewWords[index]
        }
        return union
    }

    /// The locals that this set holds and `other`, a set of the same function's locals, leaves out, in the order of
    /// their IDs.
    package func locals(notIn other: LocalSet) -> [LocalID] {
        // Of a set of many, only the words that differ from the other set's are looked at.
        let words = fewWords.isEmpty ? manyWords.indices(differingFrom: other.manyWords) : Array(fewWords.indices)
        var locals: [LocalID] = []
        for index in words {
            // Each bit left in the word stands for one local, lowest first.
            var bits = word(at: index) & ~other.word(at: index)
            while bits != 0 {
                locals.append(LocalID(index: index * UInt64.bitWidth + bits.trailingZeroBitCount))
                bits &= bits - 1
            }
        }
        return locals
    }

    private func word(at index: Int) -> UInt64 {
        fewWords.isEmpty ? manyWords[index] : fewWords[index]
    }

    private mutating func setWord(_ word: UInt64, at index: Int) {
        if fewWords.isEmpty {
            manyWords[index] = word
        } else {
            fewWords[index] = word
        }
    }

    private static func word(of local: LocalID) -> Int {
        local.index / UInt64.bitWidth
    }

    private static func bit(of local: LocalID) -> UInt64 {
        1 << UInt64(local.index % UInt64.bitWidth)
    }
}
