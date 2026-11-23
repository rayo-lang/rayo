import RayoCheckedProgram

/// The locals of a function that some path to a point retired, with no declaration after it to start them again.
struct RetiredLocals: DataflowState {
    /// A bit for each local, indexed by `LocalID`, set where it is retired. Blocks change few words, so their states
    /// share the rest.
    private var words: PersistentArray<UInt64>

    /// The state on entry to `body`, where no local is retired.
    init(entering body: IRBody) {
        let wordCount = (body.locals.count + UInt64.bitWidth - 1) / UInt64.bitWidth
        words = PersistentArray(Array(repeating: 0, count: wordCount))
    }

    var direction: DataflowDirection { .forward }

    func contains(_ local: LocalID) -> Bool {
        words[Self.word(of: local)] & Self.bit(of: local) != 0
    }

    func merged(with other: RetiredLocals) -> RetiredLocals {
        var merged = self
        merged.words = words.merged(with: other.words) { $0 | $1 }
        return merged
    }

    mutating func apply(_ effect: Effect, in function: Void) {
        switch effect {
        case .declare(let local):
            words[Self.word(of: local)] &= ~Self.bit(of: local)
        case .retire(let local):
            words[Self.word(of: local)] |= Self.bit(of: local)
        case .read, .move, .store, .begin, .use, .end, .depend, .exit:
            break
        }
    }

    private static func word(of local: LocalID) -> Int {
        local.index / UInt64.bitWidth
    }

    private static func bit(of local: LocalID) -> UInt64 {
        1 << UInt64(local.index % UInt64.bitWidth)
    }
}
