import RayoIR

/// The accesses that some path to a point of a function has not begun, which no end there may end.
struct UnbegunAccessState: DataflowState {
    /// Whether some path hasn't begun each access, indexed by `AccessID`. Blocks begin few accesses, so their states
    /// share the rest.
    private var isUnbegun: PersistentArray<Bool>

    var direction: DataflowDirection { .forward }

    /// The state on entry to a function that numbers its accesses below `accessCount`, none of which any path has
    /// begun yet.
    init(accessCount: Int) {
        isUnbegun = PersistentArray(Array(repeating: true, count: accessCount))
    }

    func merged(with other: UnbegunAccessState) -> UnbegunAccessState {
        var merged = self
        merged.isUnbegun = isUnbegun.merged(with: other.isUnbegun) { $0 || $1 }
        return merged
    }

    /// Whether some path to the point hasn't begun `access`.
    func contains(_ access: AccessID) -> Bool {
        isUnbegun[access.index]
    }

    mutating func apply(_ effect: Effect, in function: Void) {
        guard case .begin(let id, _) = effect else { return }
        isUnbegun[id.index] = false
    }
}
