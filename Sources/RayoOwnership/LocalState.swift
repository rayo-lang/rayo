import RayoIR
import RayoSource

/// What a local, and each place moved out of it, holds at a point of a function. Each place it is asked about lies in
/// the local.
struct LocalState: Equatable {
    /// What the local holds as a whole, apart from the places moved out of it.
    private(set) var whole: PlaceState
    /// What each place moved out of the local holds since, on the paths that reach the point. A place left out holds
    /// a value wherever the local does, so none here holds a value on every path.
    private var movedParts: [Place: PlaceState] = [:]

    static let initialized = LocalState(whole: .initialized)
    static let declared = LocalState(whole: .declared)

    private init(whole: PlaceState) {
        self.whole = whole
    }

    /// Why a use of `place` may find no value there, or nil where it finds one on every path.
    func missingValue(forUseOf place: Place) -> MissingValue? {
        missingValue(onPathTo: place, through: place.steps.count) ?? movedPart(inside: place)
    }

    /// Why a store to `place`, a part of the local, may find no value around it, which the store needs to change part
    /// of, or nil where it finds one on every path.
    func missingValue(forStoreTo place: Place) -> MissingValue? {
        missingValue(onPathTo: place, through: place.steps.count - 1)
    }

    /// Takes the value of `place`.
    mutating func move(_ place: Place, at range: SourceRange) {
        // A move of the whole local takes every part with it.
        guard !place.steps.isEmpty else {
            whole = whole.moved(at: range)
            movedParts = [:]
            return
        }

        // A move of a part takes the parts inside it too, so its own state stands for theirs.
        let state = movedParts[place] ?? .initialized
        forgetParts(inside: place)
        movedParts[place] = state.moved(at: range)
    }

    /// Gives `place` a value.
    mutating func assign(_ place: Place) {
        // A whole value replaces the local's, parts and all.
        guard !place.steps.isEmpty else {
            self = .initialized
            return
        }

        // A part's new value replaces the values of the parts inside it too.
        forgetParts(inside: place)
    }

    /// What a local holds where a path on which it holds `self` joins one on which it holds `other`.
    func joined(with other: LocalState) -> LocalState {
        var joined = LocalState(whole: whole.joined(with: other.whole))
        for place in Set(movedParts.keys).union(other.movedParts.keys) {
            // A part that one path left out holds a value on that path wherever the local does.
            let state = movedParts[place] ?? .initialized
            joined.movedParts[place] = state.joined(with: other.movedParts[place] ?? .initialized)
        }
        return joined
    }

    /// Why the local, or one of the places that the first `depth` steps to `place` lead to, may hold no value, or nil
    /// where each holds one on every path.
    private func missingValue(onPathTo place: Place, through depth: Int) -> MissingValue? {
        // A local that may hold no value holds none of its parts either.
        guard whole.isInitialized else {
            return MissingValue(kind: .placeOrHolder, place: Place(root: place.root), state: whole)
        }

        // Step down the path, outermost first.
        for length in 0..<depth {
            let holder = place.prefix(length + 1)
            // The first part moved out on the way down is the one that leaves the place without its value.
            if let state = movedParts[holder] { return MissingValue(kind: .placeOrHolder, place: holder, state: state) }
        }
        return nil
    }

    /// The first part, in the order of its steps, that may have been moved out from inside `place`.
    private func movedPart(inside place: Place) -> MissingValue? {
        let inside = movedParts.filter { $0.key.steps.count > place.steps.count && place.contains($0.key) }
        // A place with no part moved out from inside it holds all of its value.
        guard let first = inside.min(by: { $0.key.steps.lexicographicallyPrecedes($1.key.steps) }) else { return nil }
        return MissingValue(kind: .insidePlace, place: first.key, state: first.value)
    }

    /// Forgets what `place` and each part inside it held, where a move or an assignment replaces it.
    private mutating func forgetParts(inside place: Place) {
        movedParts = movedParts.filter { !place.contains($0.key) }
    }
}
