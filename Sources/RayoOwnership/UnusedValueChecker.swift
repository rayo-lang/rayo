import RayoDiagnostics
import RayoIR
import RayoSema

/// Checks that some code reads each value a program assigns to a local, or to a field inside one.
public enum UnusedValueChecker {
    /// Reports each place that assigns a local, or a field inside one, a value that no code reads, in source order.
    public static func check(_ program: IRProgram) -> [Diagnostic] {
        program.functions.flatMap { check($0, types: program.types) }.inSourceOrder
    }

    private static func check(_ function: IRFunction, types: TypeTable) -> [Diagnostic] {
        var errors: [Diagnostic] = []
        let analysis = LivenessAnalysis(function)
        for case (let block, var state?) in zip(function.blocks, analysis.exitStates) {
            state.apply(backwardsThrough: block) { destination, isRead in
                // A store that some code reads leaves nothing to report.
                guard !isRead else { return }
                // Lowering reads each temporary it writes, so only a local of the source leaves a value unread.
                guard let name = sourceName(of: destination, in: function, types: types) else { return }
                errors.append(Diagnostic(.unreadValue(name: name), at: destination.range))
            }
        }
        return errors
    }

    /// The name of `place` as the source writes it, such as `e.stats.hp`, or nil where it lies in a temporary.
    private static func sourceName(of place: Place, in function: IRFunction, types: TypeTable) -> String? {
        // A temporary has no name in the source.
        guard case .source(var name, _, var type) = function.locals[place.local.index] else { return nil }

        // Each field steps into the struct that holds it, which declares the field's name.
        for field in place.fields {
            guard case .structure(let id) = type else { preconditionFailure("only a struct holds a field") }
            let declared = types[id].fields[field]
            name += "." + declared.name
            type = declared.type
        }
        return name
    }
}
