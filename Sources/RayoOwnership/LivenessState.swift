import RayoIR
import RayoSema

/// Which locals, and which parts inside them, hold a value that some code reads later, at a point.
struct LivenessState: DataflowState {
    /// The places whose values some code reads later; a read of a place reads every part inside it too.
    private var live: Set<Place> = []

    /// The state at the end of a function, after which no code reads any local.
    init() {}

    func merged(with other: LivenessState) -> LivenessState {
        var merged = self
        merged.live.formUnion(other.live)
        return merged
    }

    /// Whether some code reads the value that a store to `place` just before this state leaves there: a later read
    /// of the place, of a part that may lie inside it, or of a value that may hold it.
    func reads(_ place: Place) -> Bool {
        live.contains { place.overlaps($0) }
    }

    /// Takes the state after `terminator` back to the state before it.
    mutating func apply(backwardsThrough terminator: Terminator) {
        // A terminator without an operand reads no place.
        guard let operand = terminator.operand else { return }
        apply(operand)
    }

    /// Takes the state after `statement`, a statement of the function whose places `places` gives the types of, back
    /// to the state before it.
    mutating func apply(backwardsThrough statement: Statement, in places: PlaceTypes) {
        switch statement {
        // A computation reads its operands before it stores to its destination, so going backwards it stores
        // first.
        case .compute(let destination, let value, _):
            // A computation with a destination stores a value in its place.
            if let destination { assign(destination.place, in: places) }
            value.operands.forEach { apply($0) }

        // A declaration starts its local's life, so no code before it reads a value the local holds after it.
        case .declare(let local):
            live = live.filter { $0.root != local }

        // An access reaches the value its place holds, whether it reads it or changes it.
        case .begin(_, let access):
            read(access.place)

        // Ending an access, or depending on one, reads no place.
        case .end, .depend:
            break
        }
    }

    /// Leaves what `stored` held before a store to it unread by any code after the store.
    private mutating func assign(_ stored: Place, in places: PlaceTypes) {
        // The store replaces the place's value, and the values of the parts inside it.
        live = live.filter { !stored.contains($0) }
        narrowHolders(of: stored, in: places)
    }

    /// Narrows each live place that holds `stored` inside it to the fields beside the path down to `stored`, at each
    /// level, since a store to `stored` leaves only their values for a later read of the holder.
    private mutating func narrowHolders(of stored: Place, in places: PlaceTypes) {
        let holders = live.filter { $0.contains(stored) }
        for holder in holders {
            live.remove(holder)

            // At each level from the holder down, the fields beside the one on the path to `stored` stay live.
            for depth in holder.steps.count..<stored.steps.count {
                let level = stored.prefix(depth)
                let count = places.fields(ofStructAt: level).count
                for field in 0..<count where PlaceStep.field(field) != stored.steps[depth] {
                    live.insert(level.appending(.field(field)))
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
        case .read(let place, _), .move(let place, _):
            read(place)
        }
    }

    /// Reads the value at `place`, and the locals that hold the indices it finds its elements by.
    private mutating func read(_ place: Place) {
        live.insert(place)
        live.formUnion(place.indexLocals.map { Place(root: $0) })
    }
}
