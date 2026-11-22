import RayoCheckedProgram
import RayoDiagnostics
import RayoIR

/// Works out where each access of a function ends, checks the law of exclusivity over those extents, and writes the
/// ends into the function's body.
enum ExclusivityChecker {
    /// The body whose places `places` gives the types of, with the end of each access written in after the access's
    /// last live point on each path, and the conflicts between its accesses. `uses` says what code after each point of
    /// the body uses.
    static func check(
        _ places: PlaceTypes, uses: DataflowResults<AccessUseState>,
    ) -> (body: IRBody, errors: [Diagnostic]) {
        // A body that begins no access has none to end, and none that a change could conflict with.
        let accesses = places.body.begunAccesses
        guard !accesses.isEmpty else { return (places.body, []) }

        // Work out where each access is live, at each point of each block, and where it is held: live where every
        // path has begun it.
        let extents = AccessExtents(places.body, uses: uses)
        let blocks = places.body.blocks.indices.map { BlockID(index: $0) }
        let live = blocks.map { extents.live(in: $0) }
        let held = blocks.map { block in live[block.index].map { extents.held(in: block, live: $0) } }

        // Check each block that a path reaches; one that none reaches runs no access.
        var conflicts = AccessConflicts(places: places, accesses: accesses)
        for (block, blockLive) in zip(blocks, live) {
            guard let blockLive else { continue }
            conflicts.check(block, live: blockLive)
        }

        return (AccessEnds.written(into: places.body, held: held), conflicts.errors)
    }
}
