/// Why a use of a place may find no value there: the local, or a field of it, that may hold none.
struct MissingValue {
    /// Where the local or field that may hold no value lies, as the used place sees it.
    enum Kind {
        /// It is the place, or holds the place.
        case placeOrHolder
        /// It lies inside the place, which may then hold only part of its value.
        case insidePlace
    }

    var kind: Kind
    /// The fields that lead from the local to the local or field that may hold no value, outermost first; none for
    /// the local itself.
    var fields: [Int]
    /// What that local or field holds.
    var state: PlaceState
}
