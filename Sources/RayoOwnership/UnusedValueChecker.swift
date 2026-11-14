import RayoDiagnostics
import RayoIR
import RayoSema

/// Checks that some code reads each value a program assigns to a local, or to a field inside one.
public enum UnusedValueChecker {
    /// Reports each place that assigns a local, or a field inside one, a value that no code reads, under the ID of
    /// each function that has any, in source order.
    public static func check(_ program: IRProgram) -> [FunctionID: [Diagnostic]] {
        program.errors { check(PlaceTypes(body: $1, types: program.types)) }
    }

    /// Checks the body whose places `places` gives the types of.
    private static func check(_ places: PlaceTypes) -> [Diagnostic] {
        var results = DataflowSolver.solve(LivenessAnalysis(places: places), in: places.body)
        return places.body.blocks.indices.flatMap { errors(in: BlockID(index: $0), of: places, results: &results) }
    }

    /// The stores in `block` of a value that no code reads, where `results` say what code reads after each of them.
    private static func errors(
        in block: BlockID, of places: PlaceTypes, results: inout DataflowResults<LivenessAnalysis>,
    ) -> [Diagnostic] {
        // Asking from the last statement back walks the block once, the way liveness flows.
        let indices = places.body.blocks[block.index].statements.indices.reversed()
        return indices.compactMap { error(at: $0, in: block, of: places, results: &results) }
    }

    /// The error at the statement at `index` in `block`, where it stores a value that no code reads, or nil where it
    /// doesn't.
    private static func error(
        at index: Int, in block: BlockID, of places: PlaceTypes, results: inout DataflowResults<LivenessAnalysis>,
    ) -> Diagnostic? {
        // Only a computation with a destination stores a value.
        guard case .compute(let destination?, _, _) = places.body.blocks[block.index].statements[index] else {
            return nil
        }
        // A block that no path reaches has no state, and nothing in it is checked.
        guard let state = results.state(after: index, in: block) else { return nil }
        // A store that some code reads leaves nothing to report.
        guard !state.reads(destination.place) else { return nil }
        // Lowering reads each temporary it writes, so only a local of the source leaves a value unread.
        guard let name = places.sourceName(of: destination.place) else { return nil }
        return Diagnostic(.unreadValue(name: name), at: destination.range)
    }
}
