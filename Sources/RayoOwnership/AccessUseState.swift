import RayoIR

/// What code after a point uses: the accesses it passes, and the values it reads.
struct AccessUseState: DataflowState {
    /// The accesses that some code after the point uses.
    private(set) var accesses = LiveAccesses()
    /// The values that some code after the point reads.
    private(set) var values = LivenessState()

    var direction: DataflowDirection { .backward }

    /// The state at the end of a function, after which no code uses anything.
    init() {}

    func merged(with other: AccessUseState) -> AccessUseState {
        var merged = self
        merged.accesses = accesses.merged(with: other.accesses)
        merged.values = values.merged(with: other.values)
        return merged
    }

    /// Takes the state across `effect`, an effect in the function whose places `places` gives the types of.
    mutating func apply(_ effect: Effect, in places: PlaceTypes) {
        accesses.apply(effect, in: ())
        values.apply(effect, in: places)
    }
}
