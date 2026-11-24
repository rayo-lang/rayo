/// How code changes a place.
package enum PlaceChange: Equatable, Sendable {
    /// Stores a value in the place, as an assignment does.
    case store
    /// Lends the place for change, as a `mutable` argument does.
    case modify
}
