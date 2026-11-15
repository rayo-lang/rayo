import RayoIR
import RayoSema

/// Which locals, and which parts inside them, hold a value that some code reads later, at a point.
struct LivenessState: DataflowState {
    /// The places whose values some code reads later, each but the elements that stores replace before every read,
    /// by the local they lie in, so that a store or a declaration changes only the reads of its own local. Each place
    /// keeps one read, which stands for the reads on every path, so the state grows with the places a function names
    /// and not with its paths. A local whose values no code reads later is left out.
    private var live: [LocalID: [Place: LiveRead]] = [:]

    /// The state at the end of a function, after which no code reads any local.
    init() {}

    func merged(with other: LivenessState) -> LivenessState {
        var merged = self
        for read in other.live.values.flatMap(\.values) { merged.add(read) }
        return merged
    }

    /// Whether some code reads the value that a store to `place` just before this state leaves there: a later read
    /// of the place, of a part that may lie inside it, or of a value that may hold it.
    func reads(_ place: Place) -> Bool {
        live[place.root]?.values.contains { $0.mayReach(place) } ?? false
    }

    /// The locals holding a value, in whole or in part, that some code reads later.
    var readLocals: Set<LocalID> {
        Set(live.keys)
    }

    /// Takes the state after `terminator`, a terminator of `body`, back to the state before it.
    mutating func apply(backwardsThrough terminator: Terminator, of body: IRBody) {
        // A return reads each parameter whose value the caller reads once the function returns.
        if case .return = terminator {
            for (index, local) in body.locals.enumerated() where local.parameterConvention?.isReadAtReturn == true {
                read(Place(root: LocalID(index: index)))
            }
        }

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
            live[local] = nil

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
        removeReads(in: stored.root) { stored.mustContain($0.place) }
        narrowHolders(of: stored, in: places)
    }

    /// Narrows each live read of a place that holds `stored` inside it to the parts beside the path down to `stored`,
    /// at each level, since a store to `stored` leaves only their values for that read.
    private mutating func narrowHolders(of stored: Place, in places: PlaceTypes) {
        // A read that already skips the element `stored` lies in leaves it to a later store, and stays as it is.
        let isHolder = { (read: LiveRead) in read.place.mustContain(stored) && read.mayReach(stored) }
        let holders = live[stored.root]?.values.filter(isHolder) ?? []

        // Every holder leaves before any narrowed read joins the read live at its place, since a holder still live
        // there would cover the elements the narrowed read skips.
        removeReads(in: stored.root, where: isHolder)

        for holder in holders {
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
            if narrowed.skippedElements.count < count { add(narrowed) }

        // A struct's other fields stay live one by one.
        case let holder:
            for field in places.types.fields(of: holder).indices where PlaceStep.field(field) != step {
                add(LiveRead(place: read.place.appending(.field(field))))
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
        add(LiveRead(place: place))
        for local in place.indexLocals { add(LiveRead(place: Place(root: local))) }
    }

    /// Adds `read` to the read live at its place, which then stands for both.
    private mutating func add(_ read: LiveRead) {
        live[read.place.root, default: [:]][read.place, default: read].cover(read)
    }

    /// Removes the reads of places in `local` that `isRemoved` picks, and leaves the local out once none is left.
    private mutating func removeReads(in local: LocalID, where isRemoved: (LiveRead) -> Bool) {
        guard let reads = live.removeValue(forKey: local) else { return }
        let kept = reads.filter { !isRemoved($0.value) }
        if !kept.isEmpty { live[local] = kept }
    }
}

/// A later read of the value at `place`, and of every part inside it, but for the elements of the array it holds at
/// `skippedElements`, whose values stores replace before the read.
private struct LiveRead: Equatable {
    let place: Place
    private(set) var skippedElements: Set<Int> = []

    init(place: Place) {
        self.place = place
    }

    /// Whether the read may reach the value that a store to `stored` leaves: whether `stored` may overlap the place,
    /// outside the skipped elements.
    func mayReach(_ stored: Place) -> Bool {
        guard place.mayOverlap(stored) else { return false }

        // A store into a skipped element, which the place must contain, is replaced again before the read.
        let depth = place.steps.count
        guard place.mustContain(stored), stored.steps.count > depth, case .element(let index) = stored.steps[depth]
        else { return true }
        return !skippedElements.contains(index)
    }

    /// The same read, skipping the element at `index` too.
    func skipping(_ index: Int) -> LiveRead {
        var narrowed = self
        narrowed.skippedElements.insert(index)
        return narrowed
    }

    /// Widens the read to also cover `other`, a read of the same place. An element stays skipped only where both skip
    /// it, since a store must replace it before each of them to leave its value unread.
    mutating func cover(_ other: LiveRead) {
        skippedElements.formIntersection(other.skippedElements)
    }
}
