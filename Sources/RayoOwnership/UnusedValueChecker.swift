import RayoDiagnostics
import RayoIR
import RayoSema

/// Checks that some code reads each value a program assigns to a local, or to a field inside one.
public enum UnusedValueChecker {
    /// Reports each place that assigns a local, or a field inside one, a value that no code reads, in source order.
    public static func check(_ program: IRProgram) -> [Diagnostic] {
        program.functions.flatMap { check(PlaceTypes(function: $0, types: program.types)) }.inSourceOrder
    }

    /// Checks the function whose places `places` gives the types of.
    private static func check(_ places: PlaceTypes) -> [Diagnostic] {
        var errors: [Diagnostic] = []
        let analysis = LivenessAnalysis(of: places)
        for case (let block, var state?) in zip(places.function.blocks, analysis.exitStates) {
            state.apply(backwardsThrough: block, in: places) { destination, isRead in
                // A store that some code reads leaves nothing to report.
                guard !isRead else { return }
                // Lowering reads each temporary it writes, so only a local of the source leaves a value unread.
                guard let name = sourceName(of: destination, in: places) else { return }
                errors.append(Diagnostic(.unreadValue(name: name), at: destination.range))
            }
        }
        return errors
    }

    /// The name of `place` as the source writes it, such as `e.stats.hp`, or nil where it lies in a temporary.
    private static func sourceName(of place: Place, in places: PlaceTypes) -> String? {
        // A temporary has no name in the source.
        guard case .source(let local, _, _) = places.function.locals[place.local.index] else { return nil }

        // Each field takes its name from the struct that holds it.
        let fields = place.fields.indices.map { depth in
            places.fields(ofStructIn: place.local, at: place.fields.prefix(depth))[place.fields[depth]].name
        }
        return ([local] + fields).joined(separator: ".")
    }
}
