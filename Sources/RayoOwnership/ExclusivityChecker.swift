import RayoDiagnostics
import RayoIR
import RayoSema

/// Works out where each access of a program ends, checks the law of exclusivity over those extents, and writes the
/// ends into the program, which the emitter then receives.
public enum ExclusivityChecker {
    /// The program with the end of each access written into each function's body, after the access's last live
    /// point on each path, and the conflicts between accesses, under the ID of each function that has any, in source
    /// order.
    public static func check(_ program: IRProgram) -> (program: IRProgram, errors: [FunctionID: [Diagnostic]]) {
        var ended = program
        let errors = program.errors { id, body in
            let (endedBody, errors) = check(PlaceTypes(body: body, types: program.types))
            ended.bodies[id] = endedBody
            return errors
        }
        return (ended, errors)
    }

    /// The body whose places `places` gives the types of, with its accesses' ends written into it, and the
    /// conflicts between its accesses.
    private static func check(_ places: PlaceTypes) -> (body: IRBody, errors: [Diagnostic]) {
        // A body that begins no access has none to end, and none that a change could conflict with.
        let accesses = places.body.begunAccesses
        guard !accesses.isEmpty else { return (places.body, []) }

        // Work out where each access is live, at each point of each block, and where every path has begun it.
        var extents = AccessExtents(places)
        let blocks = places.body.blocks.indices.map { BlockID(index: $0) }
        let live = blocks.map { extents.live(in: $0) }
        let held = zip(live, blocks.map { extents.unbegun(in: $0) }).map(Self.held)

        // Check each block that a path reaches; one that none reaches runs no access.
        var conflicts = AccessConflicts(places: places, accesses: accesses)
        for (block, blockLive) in zip(blocks, live) {
            guard let blockLive else { continue }
            conflicts.check(block, live: blockLive)
        }

        return (AccessEnds.written(into: places.body, held: held), conflicts.errors)
    }

    /// The accesses held at each point of a block, where `live` are those live there and `unbegun` those that some
    /// path there hasn't begun: those live that every path has begun. Only they can end there, since a path that
    /// hasn't begun an access has nothing to end. Nil where no path reaches the block.
    private static func held(live: [Set<AccessID>]?, unbegun: [Set<AccessID>]?) -> [Set<AccessID>]? {
        guard let live, let unbegun else { return nil }
        return zip(live, unbegun).map { $0.subtracting($1) }
    }
}
