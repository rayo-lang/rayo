import RayoIR

/// The accesses that some path to a point of a function has not begun, which no end there may end.
struct UnbegunAccessState: DataflowState {
    private(set) var accesses: Set<AccessID>

    var direction: DataflowDirection { .forward }

    /// The state on entry to a function that begins `accesses`, none of which any path has begun yet.
    init(_ accesses: Set<AccessID>) {
        self.accesses = accesses
    }

    func merged(with other: UnbegunAccessState) -> UnbegunAccessState {
        UnbegunAccessState(accesses.union(other.accesses))
    }

    mutating func apply(_ effect: Effect, in function: Void) {
        guard case .begin(let id, _) = effect else { return }
        accesses.remove(id)
    }
}
