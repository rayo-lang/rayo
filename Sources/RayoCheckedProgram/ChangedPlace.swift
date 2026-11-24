/// What decides whether code may change a place that starts from a local of the source: the local's kind, and whether
/// the place is the local whole or a part inside it.
package struct ChangedPlace {
    /// The kind of the local the place starts from.
    package var local: LocalKind
    /// Whether the place is a part inside the local, and not the local whole.
    package var isPart: Bool

    package init(local: LocalKind, isPart: Bool) {
        self.local = local
        self.isPart = isPart
    }

    /// The kind of local that refuses `change` of the place, or nil where code may change it so.
    package func refusal(of change: PlaceChange) -> ReadOnlyLocal? {
        switch local {
        // Each owns its value, or borrows its caller's place for change, so it may change whole or part by part.
        case .var, .parameter(.owned), .parameter(.mutable): nil
        case .parameter(.borrowed): .borrowedParameter
        // A store gives a `let` or a `ref let` its value whole, and the initialization check says which stores may.
        case .let: givesWholeValue(change) ? nil : .let
        case .refLet: givesWholeValue(change) ? nil : .refLet
        }
    }

    /// Whether `change` stores a value in the local whole, as the store that gives a local its value does.
    private func givesWholeValue(_ change: PlaceChange) -> Bool {
        !isPart && change == .store
    }
}
