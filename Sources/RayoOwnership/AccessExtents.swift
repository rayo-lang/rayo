import RayoIR

/// Where each access of a function is live: from where it begins through the last use of the access, and of every
/// value that depends on it, on each path. Where paths join, an access is live if it is live on any of them.
struct AccessExtents {
    private let body: IRBody
    /// What each local's value depends on at each point, carried forward.
    private var dependencies: DataflowResults<DependencyAnalysis>
    /// What code after each point uses, carried backward.
    private var uses: DataflowResults<AccessUseAnalysis>

    /// The extents of the accesses of `places.body`, the body whose places `places` gives the types of.
    init(_ places: PlaceTypes) {
        body = places.body
        dependencies = DataflowSolver.solve(DependencyAnalysis(), in: places.body)
        uses = DataflowSolver.solve(AccessUseAnalysis(places: places), in: places.body)
    }

    /// The accesses live at each point of `block`: the set at index `i` is the one just before the statement at `i`,
    /// the one at the number of statements just before the terminator, and the last just after it. Nil where no path
    /// reaches the block.
    mutating func live(in block: BlockID) -> [Set<AccessID>]? {
        let points = 0...body.blocks[block.index].statements.count + 1

        // Ask each analysis about the points in its own direction, so that each walks the block once.
        var dependencyStates: [DependencyState] = []
        for point in points {
            guard let state = state(at: point, in: block, of: &dependencies) else { return nil }
            dependencyStates.append(state)
        }
        var useStates: [AccessUseState] = []
        for point in points.reversed() {
            guard let state = state(at: point, in: block, of: &uses) else { return nil }
            useStates.append(state)
        }

        return zip(useStates.reversed(), dependencyStates).map { Self.live(using: $0, dependingOn: $1) }
    }

    /// The state that `results` settle on at `point` of `block`, counted as `live(in:)` counts its points; nil where
    /// no path reaches the block.
    private func state<Analysis>(
        at point: Int, in block: BlockID, of results: inout DataflowResults<Analysis>,
    ) -> Analysis.State? {
        let terminator = body.blocks[block.index].statements.count
        return point <= terminator
            ? results.state(before: point, in: block) : results.state(after: terminator, in: block)
    }

    /// The accesses live at a point where later code uses what `uses` holds, and values depend on what
    /// `dependencies` holds: those the code uses, those they depend on, and those that the values it reads depend on.
    private static func live(using uses: AccessUseState, dependingOn dependencies: DependencyState) -> Set<AccessID> {
        var live = uses.accesses
        for access in uses.accesses {
            live.formUnion(dependencies.dependencies(of: access))
        }
        for (local, accesses) in dependencies.dependentLocals where uses.values.reads(Place(root: local)) {
            live.formUnion(accesses)
        }
        return live
    }
}
