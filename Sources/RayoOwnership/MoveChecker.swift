import RayoDiagnostics
import RayoIR

/// Checks that a program uses each local only where it holds a value, which a move takes out of it.
public enum MoveChecker {
    /// Reports each use of a local that a move may have left without a value, in source order.
    public static func check(_ program: IRProgram) -> [Diagnostic] {
        program.functions.flatMap(check).sorted { $0.range.start < $1.range.start }
    }

    private static func check(_ function: IRFunction) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        let analysis = InitializationAnalysis(function)
        for (block, entryState) in zip(function.blocks, analysis.entryStates) {
            guard var state = entryState else { continue }
            state.apply(block) { place, initialization in
                guard let code = error(using: place, holding: initialization, in: function) else { return }
                diagnostics.append(Diagnostic(code, at: place.range))
            }
        }
        return diagnostics
    }

    /// The error for a use of `place` where its local holds `initialization`, or nil when it holds a value.
    private static func error(using place: Place, holding initialization: Initialization,
                              in function: IRFunction) -> ErrorCode? {
        guard initialization != .initialized else { return nil }
        // Each local the source declares gets a value where it is declared, and lowering writes each temporary
        // before it reads it, so only a move leaves a local without a value at a use.
        guard let name = function.locals[place.local.index].name else {
            preconditionFailure("lowering moves no temporary, and reads one only once it has written it")
        }
        return initialization == .maybe ? .usedAfterMaybeMove(name: name) : .usedAfterMove(name: name)
    }
}
