import RayoSource

/// What a local holds at a point of a function. On each path that reaches the point, the local holds a value,
/// holds none because nothing has assigned it since its declaration, or holds none because a move took its value.
struct LocalState: Equatable {
    var holdsValueOnSomePath: Bool
    var isUnassignedOnSomePath: Bool
    /// The ranges of the moves after which no assignment gives the local a value on some path to the point.
    /// Lowering gives each move a range of its own.
    var moves: Set<SourceRange>

    static let initialized = LocalState(holdsValueOnSomePath: true, isUnassignedOnSomePath: false, moves: [])
    static let declared = LocalState(holdsValueOnSomePath: false, isUnassignedOnSomePath: true, moves: [])

    /// The state after the move at `range`, which takes the local's value on the paths where it holds one.
    func moved(at range: SourceRange) -> LocalState {
        LocalState(holdsValueOnSomePath: false, isUnassignedOnSomePath: isUnassignedOnSomePath,
                   moves: holdsValueOnSomePath ? moves.union([range]) : moves)
    }

    /// Whether the local holds a value on every path.
    var isInitialized: Bool {
        !isUnassignedOnSomePath && moves.isEmpty
    }

    /// Whether an assignment has given the local a value on some path, though a move may have taken it since.
    var isAssignedOnSomePath: Bool {
        holdsValueOnSomePath || !moves.isEmpty
    }

    /// What a local holds where a path on which it holds `self` joins one on which it holds `other`.
    func joined(with other: LocalState) -> LocalState {
        LocalState(holdsValueOnSomePath: holdsValueOnSomePath || other.holdsValueOnSomePath,
                   isUnassignedOnSomePath: isUnassignedOnSomePath || other.isUnassignedOnSomePath,
                   moves: moves.union(other.moves))
    }
}
