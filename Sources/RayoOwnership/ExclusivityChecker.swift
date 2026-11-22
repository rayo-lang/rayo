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

        // Check each block that a path reaches against the accesses live at each of its points, and work out where
        // each is held: live where every path has begun it. A block that no path reaches runs no access.
        let extents = AccessExtents(places.body, uses: uses)
        var conflicts = AccessConflicts(places: places, accesses: accesses)
        var held: [[Set<AccessID>]?] = Array(repeating: nil, count: places.body.blocks.count)
        for block in places.body.blocks.indices.map({ BlockID(index: $0) }) {
            guard let live = extents.live(in: block) else { continue }
            conflicts.check(block, live: live)
            held[block.index] = extents.held(in: block, live: live)
        }

        return (AccessEnds.written(into: places.body, held: held), conflicts.errors)
    }
}
