import RayoSource

/// What a local, or a field inside it, holds where a use may find no value in it, as an error at the use says. On each
/// path that reaches the use, the place holds a value, holds none because nothing has assigned it since its local's
/// declaration, or holds none because a move took its value.
struct PlaceState: Equatable {
    var holdsValueOnSomePath: Bool
    var isUnassignedOnSomePath: Bool
    /// The ranges of the moves after which no assignment gives the place a value on some path to the use.
    /// Lowering gives each move a range of its own.
    var moves: Set<SourceRange>

    /// Whether a move took the place's value on every path, after an assignment gave it one.
    var isMovedOnEveryPath: Bool {
        !holdsValueOnSomePath && !isUnassignedOnSomePath
    }
}
