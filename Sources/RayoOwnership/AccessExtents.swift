import RayoIR

/// Where each access of a function is live: from where it begins through the last use of the access, and of every
/// value that depends on it, on each path. Where paths join, an access is live if it is live on any of them.
///
/// Each question is about the points of one block: index `i` is just before the statement at `i`, the number of
/// statements is just before the terminator, and the last index is just after it.
struct AccessExtents {
    private let body: IRBody
    /// What each local's value depends on at each point, carried forward.
    private var dependencies: DataflowResults<DependencyAnalysis>
    /// What code after each point uses, carried backward.
    private var uses: DataflowResults<AccessUseAnalysis>
    /// The accesses that some path to each point has not begun, carried forward.
    private var unbegun: DataflowResults<UnbegunAccessAnalysis>

    /// The extents of the accesses of `places.body`, the body whose places `places` gives the types of.
    init(_ places: PlaceTypes) {
        body = places.body
        dependencies = DataflowSolver.solve(DependencyAnalysis(), in: places.body)
        uses = DataflowSolver.solve(AccessUseAnalysis(places: places), in: places.body)
        unbegun = DataflowSolver.solve(UnbegunAccessAnalysis(places.body), in: places.body)
    }

    /// The accesses live at each point of `block`; nil where no path reaches the block.
    mutating func live(in block: BlockID) -> [Set<AccessID>]? {
        guard let dependencyStates = states(in: block, of: &dependencies),
              let useStates = states(in: block, of: &uses)
        else { return nil }
        return zip(useStates, dependencyStates).map { Self.live(using: $0, dependingOn: $1) }
    }

    /// The accesses that some path to each point of `block` has not begun; nil where no path reaches the block.
    mutating func unbegun(in block: BlockID) -> [Set<AccessID>]? {
        states(in: block, of: &unbegun)?.map(\.accesses)
    }

    /// The states that `results` settle on at each point of `block`, asked for in the analysis's own direction, so
    /// that it walks the block once; nil where no path reaches the block.
    private func states<Analysis>(
        in block: BlockID, of results: inout DataflowResults<Analysis>,
    ) -> [Analysis.State]? {
        let terminator = body.blocks[block.index].statements.count
        let points = Array(0...terminator + 1)
        let backward = results.direction == .backward

        var states: [Analysis.State] = []
        for point in backward ? points.reversed() : points {
            let state = point <= terminator
                ? results.state(before: point, in: block) : results.state(after: terminator, in: block)
            guard let state else { return nil }
            states.append(state)
        }
        return backward ? states.reversed() : states
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
