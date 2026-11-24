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

        // Work out where each access is live, at each point of each block and after each of its effects.
        let extents = AccessExtents(places.body, uses: uses)
        let effects = places.body.blocks.map(\.effects)
        let live = effects.enumerated().map { extents.live(in: BlockID(index: $0), crossing: $1) }

        // Check each block that a path reaches; one that none reaches runs no access.
        var conflicts = AccessConflicts(places: places, accesses: accesses)
        for (blockEffects, blockLive) in zip(effects, live) {
            guard let blockLive else { continue }
            conflicts.check(blockEffects.joined(), liveAfter: blockLive.afterEffects)
        }

        // Each access ends after the last point where it is held.
        let held = extents.held(given: live.map { $0?.atPoints })
        return (AccessEnds.written(into: places.body, held: held), conflicts.errors)
    }
}
