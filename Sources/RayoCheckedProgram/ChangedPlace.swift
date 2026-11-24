/// What decides whether code may change a place that starts from a local of the source: the local's kind, and whether
/// the place is the local whole or a part inside it.
package struct ChangedPlace {
    /// The kind of the local the place starts from.
    package var local: LocalKind
    /// Whether the place is the whole local, and not a part inside it.
    package var isWhole: Bool

    package init(local: LocalKind, isWhole: Bool) {
        self.local = local
        self.isWhole = isWhole
    }

    /// Whether code may make `change` to the place.
    package func allows(_ change: PlaceChange) -> Bool {
        switch local {
        // Each owns its value, or borrows its caller's place for change, so it may change whole or part by part.
        case .var, .parameter(.owned), .parameter(.mutable): true
        // A `&T` parameter only reads its caller's place.
        case .parameter(.borrowed): false
        // A `let` and a `ref let` change only as a store gives one its value whole. The initialization check lets a
        // `let` take one store on each path, and a `ref let` only its declaration's.
        case .let, .refLet: isWhole && change == .store
        }
    }
}
