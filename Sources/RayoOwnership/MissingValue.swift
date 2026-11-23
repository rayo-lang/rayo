import RayoIR

/// Why a use of a place may find no value there: the local, or a part of it, that may hold none, and what the paths to
/// the use leave in it.
struct MissingValue {
    /// Where the local or part that may hold no value lies, as the used place sees it.
    enum Kind {
        /// It is the place, or holds the place.
        case placeOrHolder
        /// It lies inside the place, which may then hold only part of its value.
        case insidePlace
    }

    var kind: Kind
    /// The local or part that may hold no value.
    var place: Place
    var holdsValueOnSomePath: Bool
    var isUnassignedOnSomePath: Bool
}
