import RayoIR

/// What each place the initialization check follows holds at a point of a function, as facts about the paths that
/// reach the point, a bit for each fact of each place.
struct InitializationState: DataflowState {
    typealias Function = InitializationTransfer

    /// A fact about what the paths to a point leave in a place.
    enum Fact: Int, CaseIterable {
        /// Some path leaves a value in the place.
        case holdsValue
        /// Some path assigns nothing to the place after its local's declaration.
        case unassigned
        /// Some path leaves no value in the place, because nothing assigned it or a move took its value.
        case lacksValue
        /// Some path assigns the place after its local's declaration, though a move may take the value later.
        case assigned
    }

    /// What an effect does to one place's facts.
    enum Change {
        /// The place holds a value on every path: a store gave it one, or, for a part, its local's value holds it.
        case assign
        /// The place holds nothing, as a local does when its life starts or ends.
        case declare
        /// A move takes the value the place holds on any path.
        case move

        /// The facts the change sets, each to its value; the others keep theirs.
        var facts: [(fact: Fact, value: Bool)] {
            switch self {
            case .assign: [(.holdsValue, true), (.unassigned, false), (.lacksValue, false), (.assigned, true)]
            case .declare: [(.holdsValue, false), (.unassigned, true), (.lacksValue, true), (.assigned, false)]
            case .move: [(.holdsValue, false), (.lacksValue, true)]
            }
        }
    }

    /// A bit for each fact of each place, laid out as `bit(_:of:placeCount:)` says.
    private var facts: BitSet

    /// The state on entry to `body`, where its function's parameters, and the parts of every local, hold a value, and
    /// its other locals hold nothing yet.
    init(entering body: IRBody, tracking places: TrackedPlaces) {
        facts = BitSet(count: Self.bitCount(tracking: places))
        for number in 0..<places.count {
            let isPart = number >= body.locals.count
            let isParameter = !isPart && body.locals[number].parameterConvention != nil
            let change: Change = isPart || isParameter ? .assign : .declare
            apply([(number, change)], among: places)
        }
    }

    var direction: DataflowDirection { .forward }

    func merged(with other: InitializationState) -> InitializationState {
        var merged = self
        merged.facts.formUnion(other.facts)
        return merged
    }

    mutating func apply(_ effect: Effect, in transfer: InitializationTransfer) {
        apply(effect, among: transfer.places)
    }

    mutating func apply(acrossBlock block: BlockID, effects: [[Effect]], in transfer: InitializationTransfer) {
        transfer.blocks[block.index].apply(to: &facts)
    }

    mutating func apply(_ effect: Effect, among places: TrackedPlaces) {
        apply(Self.changes(of: effect, among: places), among: places)
    }

    func holds(_ fact: Fact, of number: Int) -> Bool {
        facts.contains(Self.bit(fact, of: number, placeCount: placeCount))
    }

    /// The local, or the part of one, that may hold no value where `place` is used, and where it lies.
    func missingValue(forUseOf place: Place, among places: TrackedPlaces) -> MissingValue? {
        missingValue(onPathTo: place, through: place.steps.count, among: places)
            ?? movedPart(inside: place, among: places)
    }

    /// The local, or the part of one, that may hold no value around `place`, a part of a local that a store changes.
    func missingValue(forStoreTo place: Place, among places: TrackedPlaces) -> MissingValue? {
        missingValue(onPathTo: place, through: place.steps.count - 1, among: places)
    }

    /// The bits of a state that follows `places`.
    static func bitCount(tracking places: TrackedPlaces) -> Int {
        Fact.allCases.count * places.count
    }

    /// The bits `effect` sets, each to its value, in a state that follows `places`.
    static func bits(changedBy effect: Effect, among places: TrackedPlaces) -> [(index: Int, value: Bool)] {
        changes(of: effect, among: places).flatMap { number, change in
            change.facts.map { (fact, value) in (bit(fact, of: number, placeCount: places.count), value) }
        }
    }

    /// The local, or one of the places the first `depth` steps to `place` lead to, that may hold no value, outermost
    /// first.
    private func missingValue(
        onPathTo place: Place, through depth: Int, among places: TrackedPlaces,
    ) -> MissingValue? {
        // A local that may hold no value holds none of its parts either.
        let local = Place(root: place.root)
        if holds(.lacksValue, of: place.root.index) { return missing(.placeOrHolder, local, numbered: place.root.index) }

        // Step down the path, outermost first: the first part a move may have taken leaves the place without it.
        for length in 0..<depth {
            let holder = place.prefix(length + 1)
            guard let number = places.number(of: holder), holds(.lacksValue, of: number) else { continue }
            return missing(.placeOrHolder, holder, numbered: number)
        }
        return nil
    }

    /// The first part, in the order of its steps, that a move may have taken from inside `place`.
    private func movedPart(inside place: Place, among places: TrackedPlaces) -> MissingValue? {
        let inside = places.parts(of: place.root).filter { number in
            places[number].steps.count > place.steps.count && place.mustContain(places[number])
                && holds(.lacksValue, of: number)
        }
        let first = inside.min { places[$0].steps.lexicographicallyPrecedes(places[$1].steps) }
        return first.map { missing(.insidePlace, places[$0], numbered: $0) }
    }

    private func missing(_ kind: MissingValue.Kind, _ place: Place, numbered number: Int) -> MissingValue {
        MissingValue(
            kind: kind, place: place, holdsValueOnSomePath: holds(.holdsValue, of: number),
            isUnassignedOnSomePath: holds(.unassigned, of: number),
        )
    }

    private static func bit(_ fact: Fact, of number: Int, placeCount: Int) -> Int {
        fact.rawValue * placeCount + number
    }

    /// What `effect` does to each place it changes.
    private static func changes(of effect: Effect, among places: TrackedPlaces) -> [(number: Int, change: Change)] {
        switch effect {
        // A move takes the place's value. The parts inside it hold a value again, since the place's facts cover them.
        case .move(let place, _):
            guard let moved = places.number(of: place) else { preconditionFailure("every moved place is tracked") }
            let inside = parts(inside: place, among: places).filter { $0 != moved }
            return inside.map { ($0, .assign) } + [(moved, .move)]

        // A store gives the place a value, and replaces the values of the parts inside it.
        case .store(let destination):
            let place = destination.place
            let whole: [(number: Int, change: Change)] = place.steps.isEmpty ? [(place.root.index, .assign)] : []
            return whole + parts(inside: place, among: places).map { ($0, .assign) }

        // A declaration, or a retirement, leaves the local holding nothing, even what an earlier pass of a loop gave
        // it, and its parts hold whatever it holds.
        case .declare(let local), .retire(let local):
            return [(local.index, .declare)] + places.parts(of: local).map { ($0, .assign) }

        // Reading a place, beginning or ending an access, or making a value depend on one, changes no value, and
        // leaving the function changes none it checks.
        case .read, .begin, .use, .end, .depend, .exit:
            return []
        }
    }

    /// The tracked parts that `place` must contain, itself among them where it is tracked.
    private static func parts(inside place: Place, among places: TrackedPlaces) -> [Int] {
        places.parts(of: place.root).filter { place.mustContain(places[$0]) }
    }

    private var placeCount: Int {
        facts.count / Fact.allCases.count
    }

    private mutating func apply(_ changes: [(number: Int, change: Change)], among places: TrackedPlaces) {
        for (number, change) in changes {
            for (fact, value) in change.facts {
                let bit = Self.bit(fact, of: number, placeCount: places.count)
                if value { facts.insert(bit) } else { facts.remove(bit) }
            }
        }
    }
}
