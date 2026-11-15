import RayoDiagnostics
import RayoIR
import RayoSema

/// Checks that some code reads each value a program assigns to a local, or to a field inside one, and each value the
/// function's entry stores in a parameter.
enum UnusedValueChecker {
    /// Reports each parameter whose value the entry stores and no code reads, where the source declares it, and each
    /// place that assigns a local, or a field inside one, a value that no code reads, in the body whose places
    /// `places` gives the types of, where `uses` says what code after each of its points uses.
    static func errors(in places: PlaceTypes, uses: DataflowResults<AccessUseAnalysis>) -> [Diagnostic] {
        var results = uses
        let parameters = unreadParameters(of: places.body, results: &results)
        return parameters
            + places.body.blocks.indices.flatMap { errors(in: BlockID(index: $0), of: places, results: &results) }
    }

    /// The parameters whose values the function's entry stores and no code reads, each reported where the source
    /// declares it, where `results` say what code reads after each point of `body`.
    private static func unreadParameters(
        of body: IRBody, results: inout DataflowResults<AccessUseAnalysis>,
    ) -> [Diagnostic] {
        // What code reads from the entry on, which every path through the function starts at.
        guard let entry = results.state(before: 0, in: BlockID(index: 0)) else { return [] }
        return body.locals.indices.compactMap { index in
            guard case .source(let name, .parameter(let convention), _, let range) = body.locals[index],
                  convention.isStoredAtEntry, !entry.values.reads(Place(root: LocalID(index: index)))
            else { return nil }
            return Diagnostic(.unreadValue(name: name), at: range)
        }
    }

    /// The stores in `block` of a value that no code reads, where `results` say what code reads after each of them.
    private static func errors(
        in block: BlockID, of places: PlaceTypes, results: inout DataflowResults<AccessUseAnalysis>,
    ) -> [Diagnostic] {
        // Asking from the last statement back walks the block once, the way liveness flows.
        let indices = places.body.blocks[block.index].statements.indices.reversed()
        return indices.compactMap { error(at: $0, in: block, of: places, results: &results) }
    }

    /// The error at the statement at `index` in `block`, where it stores a value that no code reads, or nil where it
    /// doesn't.
    private static func error(
        at index: Int, in block: BlockID, of places: PlaceTypes, results: inout DataflowResults<AccessUseAnalysis>,
    ) -> Diagnostic? {
        // Only a computation with a destination stores a value.
        guard case .compute(let destination?, _, _) = places.body.blocks[block.index].statements[index] else {
            return nil
        }
        // A block that no path reaches has no state, and nothing in it is checked.
        guard let state = results.state(after: index, in: block) else { return nil }
        // A store that some code reads leaves nothing to report.
        guard !state.values.reads(destination.place) else { return nil }
        // Lowering reads each temporary it writes, so only a local of the source leaves a value unread.
        guard let name = places.sourceName(of: destination.place) else { return nil }
        return Diagnostic(.unreadValue(name: name), at: destination.range)
    }
}
