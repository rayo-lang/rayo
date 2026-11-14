import RayoIR
import RayoSema

/// Which locals, and which parts inside them, hold a value that some code reads later, at a point.
struct LivenessState: DataflowState {
    /// The places whose values some code reads later, each but the elements that stores replace before the read.
    private var live: Set<LiveRead> = []

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
        live.contains { $0.mayReach(place) }
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
            live = live.filter { $0.place.root != local }

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
        // A store to an element at an index a local holds doesn't say which element it replaces, and a loop may store
        // a new index in that local before the next read through it, so the store leaves every value live.
        guard stored.indexLocals.isEmpty else { return }

        // The store replaces the place's value, and the values of the parts inside it.
        live = live.filter { !stored.contains($0.place) }
        narrowHolders(of: stored, in: places)
    }

    /// Narrows each live read of a place that holds `stored` inside it to the parts beside the path down to `stored`,
    /// at each level, since a store to `stored` leaves only their values for that read.
    private mutating func narrowHolders(of stored: Place, in places: PlaceTypes) {
        // A read that already skips the element `stored` lies in leaves it to a later store, and stays as it is.
        let holders = live.filter { $0.place.contains(stored) && $0.mayReach(stored) }
        for holder in holders {
            live.remove(holder)

            // The holder keeps what it reads beside the path, and so does each level below it, read whole until now.
            keepParts(of: holder, besides: stored.steps[holder.place.steps.count], in: places)
            for depth in (holder.place.steps.count + 1)..<stored.steps.count {
                keepParts(of: LiveRead(place: stored.prefix(depth)), besides: stored.steps[depth], in: places)
            }
        }
    }

    /// Keeps live what `read` reads of its place once a store replaces the part that `step` leads into.
    private mutating func keepParts(of read: LiveRead, besides step: PlaceStep, in places: PlaceTypes) {
        switch places.type(of: read.place) {
        // An array stays one read that skips the replaced element, so the cost doesn't grow with its count. Once it
        // skips every element, it reads nothing.
        case .array(let count, _):
            guard case .element(let index) = step else {
                preconditionFailure("only a store at an index the IR writes narrows a read")
            }
            let narrowed = read.skipping(index)
            if narrowed.skippedElements.count < count { live.insert(narrowed) }

        // A struct's other fields stay live one by one.
        case let holder:
            for field in places.types.fields(of: holder).indices where PlaceStep.field(field) != step {
                live.insert(LiveRead(place: read.place.appending(.field(field))))
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
        live.insert(LiveRead(place: place))
        live.formUnion(place.indexLocals.map { LiveRead(place: Place(root: $0)) })
    }
}

/// A later read of the value at `place`, and of every part inside it, but for the elements of the array it holds at
/// `skippedElements`, whose values stores replace before the read.
private struct LiveRead: Hashable {
    let place: Place
    private(set) var skippedElements: Set<Int> = []

    init(place: Place) {
        self.place = place
    }

    /// Whether the read may reach the value that a store to `stored` leaves: whether `stored` may overlap the place,
    /// outside the skipped elements.
    func mayReach(_ stored: Place) -> Bool {
        guard place.overlaps(stored) else { return false }

        // A store into a skipped element, by the same steps as the place, is replaced again before the read.
        let depth = place.steps.count
        guard stored.steps.count > depth, case .element(let index) = stored.steps[depth], stored.prefix(depth) == place
        else { return true }
        return !skippedElements.contains(index)
    }

    /// The same read, skipping the element at `index` too.
    func skipping(_ index: Int) -> LiveRead {
        var narrowed = self
        narrowed.skippedElements.insert(index)
        return narrowed
    }
}
