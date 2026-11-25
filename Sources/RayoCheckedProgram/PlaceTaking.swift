/// What a position does with a place that the source writes there bare: the use it makes of the place, and the error
/// it reports where the source must write a mark before the place.
package struct PlaceTaking: Equatable {
    /// What the position does with the place, or nil where it refuses it. Where the error leaves the body without a
    /// meaning, the use lets checking go on, and no later stage sees it.
    package var use: PlaceUse?
    package var error: PlaceError?

    package init(use: PlaceUse?, error: PlaceError? = nil) {
        self.use = use
        self.error = error
    }
}
