/// A kind of local that refuses a change of a place that starts from it.
package enum ReadOnlyLocal: Equatable, Sendable {
    /// A `&T` parameter, which only reads its caller's place.
    case borrowedParameter
    /// A `let`, which changes only as a store gives it its value whole.
    case `let`
    /// A `ref let`, which changes only as its declaration's store gives it its value whole.
    case refLet
}
