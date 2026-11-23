/// A set of the numbers below a fixed count, a bit for each, which a dataflow state uses to hold one fact about each
/// thing it follows. Merging, copying and comparing two sets cost one step for each 64 bits.
package struct BitSet: Equatable, Sequence {
    package let count: Int
    /// The bits, 64 to a word, the lowest number in the lowest bit of the first word.
    private var words: [UInt64]

    /// A set of `count` bits that holds none.
    package init(count: Int) {
        self.count = count
        words = Array(repeating: 0, count: (count + 63) / 64)
    }

    package func contains(_ bit: Int) -> Bool {
        precondition(0 <= bit && bit < count, "bit out of range")
        return words[bit / 64] & Self.mask(of: bit) != 0
    }

    package mutating func insert(_ bit: Int) {
        precondition(0 <= bit && bit < count, "bit out of range")
        words[bit / 64] |= Self.mask(of: bit)
    }

    package mutating func remove(_ bit: Int) {
        precondition(0 <= bit && bit < count, "bit out of range")
        words[bit / 64] &= ~Self.mask(of: bit)
    }

    package mutating func formUnion(_ other: BitSet) {
        combine(with: other) { $0 | $1 }
    }

    package mutating func subtract(_ other: BitSet) {
        combine(with: other) { $0 & ~$1 }
    }

    /// Replaces each word with `combine` of it and the word of `other` at the same place, one word at a time.
    package mutating func combine(with other: BitSet, using combine: (UInt64, UInt64) -> UInt64) {
        precondition(count == other.count, "combined sets have one count")
        for index in words.indices {
            words[index] = combine(words[index], other.words[index])
        }
    }

    /// The numbers the set holds, in increasing order.
    package func makeIterator() -> Iterator {
        Iterator(words: words)
    }

    package struct Iterator: IteratorProtocol {
        private let words: [UInt64]
        /// The index of the word being read, and the bits of it not yet handed out.
        private var index = 0
        private var remaining: UInt64

        fileprivate init(words: [UInt64]) {
            self.words = words
            remaining = words.first ?? 0
        }

        package mutating func next() -> Int? {
            // Skip the words with no bit left, then hand out the lowest bit left in the word.
            while remaining == 0 {
                index += 1
                guard index < words.count else { return nil }
                remaining = words[index]
            }
            let bit = remaining.trailingZeroBitCount
            remaining &= remaining - 1
            return index * 64 + bit
        }
    }

    private static func mask(of bit: Int) -> UInt64 {
        1 << UInt64(bit % 64)
    }
}
