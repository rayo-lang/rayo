import RayoDiagnostics
import RayoIR

/// Checks that some code reads each value a program assigns to a local.
public enum UnusedValueChecker {
    /// Reports each place that assigns a local a value that no code reads, in source order.
    public static func check(_ program: IRProgram) -> [Diagnostic] {
        program.functions.flatMap(check).inSourceOrder
    }

    private static func check(_ function: IRFunction) -> [Diagnostic] {
        var errors: [Diagnostic] = []
        let analysis = LivenessAnalysis(function)
        for case (let block, var state?) in zip(function.blocks, analysis.exitStates) {
            state.apply(backwardsThrough: block) { destination, isRead in
                // A value that some code reads is used.
                guard !isRead else { return }
                // Lowering reads each temporary it writes, so only a local of the source leaves a value unread.
                guard case .source(let name, _, _) = function.locals[destination.local.index] else { return }
                errors.append(Diagnostic(.unreadValue(name: name), at: destination.range))
            }
        }
        return errors
    }
}
