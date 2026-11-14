import RayoIR

/// What code after a point uses: the accesses it passes or makes a value depend on, and the values it reads. An
/// access is live at the point when code after it uses the access, or reads a value that depends on it.
struct AccessUseState: DataflowState {
    /// The accesses that some code after the point passes to a call or makes a value depend on, before any statement
    /// begins them again.
    private(set) var accesses: Set<AccessID> = []
    /// The values that some code after the point reads.
    private(set) var values = LivenessState()

    /// The state at the end of a function, after which no code uses anything.
    init() {}

    func merged(with other: AccessUseState) -> AccessUseState {
        var merged = self
        merged.accesses.formUnion(other.accesses)
        merged.values = values.merged(with: other.values)
        return merged
    }

    /// Takes the state after `terminator` back to the state before it.
    mutating func apply(backwardsThrough terminator: Terminator) {
        values.apply(backwardsThrough: terminator)
    }

    /// Takes the state after `statement`, a statement of the function whose places `places` gives the types of, back
    /// to the state before it.
    mutating func apply(backwardsThrough statement: Statement, in places: PlaceTypes) {
        values.apply(backwardsThrough: statement, in: places)
        switch statement {
        // A call uses the accesses it passes.
        case .compute(_, let value, _):
            accesses.formUnion(value.accesses)

        // Code before an access begins can't use it, whatever the code after it does.
        case .begin(let id, _):
            accesses.remove(id)

        // A dependence uses the access, which must still be live where a value comes to depend on it.
        case .depend(_, let id):
            accesses.insert(id)

        case .declare, .end:
            break
        }
    }
}
