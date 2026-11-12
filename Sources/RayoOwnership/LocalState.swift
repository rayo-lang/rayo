import RayoSource

/// What a local, and each field moved out of it, holds at a point of a function. Each field is named by the fields
/// that lead to it from the local, outermost first.
struct LocalState: Equatable {
    /// What the local holds as a whole, apart from the fields moved out of it.
    private(set) var whole: PlaceState
    /// What each field moved out of the local holds since, on the paths that reach the point. A field left out holds
    /// a value wherever the local does, so none here holds a value on every path.
    private var movedFields: [[Int]: PlaceState] = [:]

    static let initialized = LocalState(whole: .initialized)
    static let declared = LocalState(whole: .declared)

    private init(whole: PlaceState) {
        self.whole = whole
    }

    /// Why a use of the place at `fields` may find no value there, or nil where it finds one on every path.
    func missingValue(forUseOf fields: [Int]) -> MissingValue? {
        missingValue(onPathTo: fields, through: fields.count) ?? movedField(inside: fields)
    }

    /// Why a store to the field at `fields` may find no value around it, which the store needs to change part of,
    /// or nil where it finds one on every path.
    func missingValue(forStoreTo fields: [Int]) -> MissingValue? {
        missingValue(onPathTo: fields, through: fields.count - 1)
    }

    /// Takes the value of the place at `fields`.
    mutating func move(_ fields: [Int], at range: SourceRange) {
        // A move of the whole local takes every field with it.
        guard !fields.isEmpty else {
            whole = whole.moved(at: range)
            movedFields = [:]
            return
        }

        // A move of a field takes the fields inside it too, so its own state stands for theirs.
        let state = movedFields[fields] ?? .initialized
        forgetFields(inside: fields)
        movedFields[fields] = state.moved(at: range)
    }

    /// Gives the place at `fields` a value.
    mutating func assign(_ fields: [Int]) {
        // A whole value replaces the local's, fields and all.
        guard !fields.isEmpty else {
            self = .initialized
            return
        }

        // A field's new value replaces the values of the fields inside it too.
        forgetFields(inside: fields)
    }

    /// What a local holds where a path on which it holds `self` joins one on which it holds `other`.
    func joined(with other: LocalState) -> LocalState {
        var joined = LocalState(whole: whole.joined(with: other.whole))
        for fields in Set(movedFields.keys).union(other.movedFields.keys) {
            // A field that one path left out holds a value on that path wherever the local does.
            let state = movedFields[fields] ?? .initialized
            joined.movedFields[fields] = state.joined(with: other.movedFields[fields] ?? .initialized)
        }
        return joined
    }

    /// Why the local, or one of the first `depth` fields on the path to the place at `fields`, outermost first, may
    /// hold no value, or nil where each holds one on every path.
    private func missingValue(onPathTo fields: [Int], through depth: Int) -> MissingValue? {
        // A local that may hold no value holds none of its fields either.
        guard whole.isInitialized else { return MissingValue(kind: .placeOrHolder, fields: [], state: whole) }

        // Step down the path, outermost field first.
        for length in 0..<depth {
            let field = Array(fields.prefix(length + 1))
            // The first field moved out on the way down is the one that leaves the place without its value.
            if let state = movedFields[field] { return MissingValue(kind: .placeOrHolder, fields: field, state: state) }
        }
        return nil
    }

    /// The first field, in declaration order, that may have been moved out from inside the place at `fields`.
    private func movedField(inside fields: [Int]) -> MissingValue? {
        let inside = movedFields.filter { $0.key.count > fields.count && $0.key.starts(with: fields) }
        // A place with no field moved out from inside it holds all of its value.
        guard let first = inside.min(by: { $0.key.lexicographicallyPrecedes($1.key) }) else { return nil }
        return MissingValue(kind: .insidePlace, fields: first.key, state: first.value)
    }

    /// Forgets what the place at `fields` and each field inside it held, where a move or an assignment replaces it.
    private mutating func forgetFields(inside fields: [Int]) {
        movedFields = movedFields.filter { !$0.key.starts(with: fields) }
    }
}
