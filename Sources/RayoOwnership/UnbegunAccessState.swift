import RayoIR

/// The accesses that some path to a point of a function has not begun, which no end there may end.
struct UnbegunAccessState: DataflowState {
    private(set) var accesses: Set<AccessID>

    /// The state on entry to a function that begins `accesses`, none of which any path has begun yet.
    init(_ accesses: Set<AccessID>) {
        self.accesses = accesses
    }

    func merged(with other: UnbegunAccessState) -> UnbegunAccessState {
        UnbegunAccessState(accesses.union(other.accesses))
    }

    /// Applies what `statement` does to the accesses begun.
    mutating func apply(_ statement: Statement) {
        guard case .begin(let id, _) = statement else { return }
        accesses.remove(id)
    }
}
