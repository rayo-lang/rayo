import RayoIR
import RayoSema

/// Which locals, and which fields inside them, hold a value that some code reads later, at a point.
struct LivenessState: Equatable {
    /// Called with a statement's destination, and whether some code reads the value it stores there.
    typealias StoreVisitor = (Place, _ isRead: Bool) -> Void

    /// A local, or a field inside it, by the fields that lead to it from the local, outermost first.
    private struct Path: Hashable {
        var local: LocalID
        var fields: [Int]

        init(local: LocalID, fields: [Int]) {
            self.local = local
            self.fields = fields
        }

        init(_ place: Place) {
            self.init(local: place.local, fields: place.fields)
        }

        /// Whether `other` is this path's place or lies inside it.
        func contains(_ other: Path) -> Bool {
            local == other.local && other.fields.starts(with: fields)
        }
    }

    /// The places whose values some code reads later; a read of a place reads every field inside it too.
    private var live: Set<Path> = []

    /// The state at the end of a function, after which no code reads any local.
    init() {}

    /// The state where a path on which `self` holds meets one on which `other` does.
    func union(_ other: LivenessState) -> LivenessState {
        var union = self
        union.live.formUnion(other.live)
        return union
    }

    /// Takes the state after `block`, a block of the function whose places `places` gives the types of, back to the
    /// state before it, handing `store` each statement's destination.
    mutating func apply(
        backwardsThrough block: BasicBlock, in places: PlaceTypes, store: StoreVisitor = { _, _ in },
    ) {
        // The terminator's operand is the block's last read, so it comes first going backwards.
        if let operand = block.terminator.operand {
            apply(operand)
        }
        for statement in block.statements.reversed() {
            apply(statement, in: places, store: store)
        }
    }

    private mutating func apply(_ statement: Statement, in places: PlaceTypes, store: StoreVisitor) {
        switch statement {
        // A computation reads its operands before it stores to its destination, so going backwards it stores
        // first.
        case .compute(let destination, let value, _):
            // A computation with a destination stores a value in its place.
            if let destination { assign(destination, in: places, store: store) }
            value.operands.forEach { apply($0) }

        // A declaration starts its local's life, so no code before it reads a value the local holds after it.
        case .declare(let local):
            live = live.filter { $0.local != local }
        }
    }

    /// Hands `store` `destination` and whether some code reads the value stored there, then leaves what the place
    /// held before the store unread by any code after it.
    private mutating func assign(_ destination: Place, in places: PlaceTypes, store: StoreVisitor) {
        // A later read of the place, of a field inside it, or of a struct that holds it reads the stored value.
        let stored = Path(destination)
        let isRead = live.contains { stored.contains($0) || $0.contains(stored) }
        store(destination, isRead)

        // The store replaces the place's value, and the values of the fields inside it.
        live = live.filter { !stored.contains($0) }
        narrowHolders(of: stored, in: places)
    }

    /// Narrows each live place that holds `stored` inside it to the fields beside the path down to `stored`, at each
    /// level, since a store to `stored` leaves only their values for a later read of the holder.
    private mutating func narrowHolders(of stored: Path, in places: PlaceTypes) {
        let holders = live.filter { $0.contains(stored) }
        for holder in holders {
            live.remove(holder)

            // At each level from the holder down, the fields beside the one on the path to `stored` stay live.
            for depth in holder.fields.count..<stored.fields.count {
                let level = Array(stored.fields.prefix(depth))
                let count = places.fields(ofStructIn: stored.local, at: level).count
                for field in 0..<count where field != stored.fields[depth] {
                    live.insert(Path(local: stored.local, fields: level + [field]))
                }
            }
        }
    }

    private mutating func apply(_ operand: Operand) {
        switch operand {
        // A constant names no local.
        case .constant:
            break

        // A read and a move both read the value the place holds.
        case .read(let place), .move(let place):
            live.insert(Path(place))
        }
    }
}
