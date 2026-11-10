import RayoDiagnostics
import RayoIR
import RayoSema
import RayoSource

/// Checks that a program uses each local only where it holds a value, and assigns each `let` at most once on each
/// path.
public enum InitializationChecker {
    /// Reports the uses of locals that may hold no value, and the assignments to `let`s that may already have been
    /// assigned, in source order.
    public static func check(_ program: IRProgram) -> [Diagnostic] {
        // A use and a store share a place in a compound assignment, which uses the local before it stores to it,
        // so errors at one place keep the order each function gives them.
        program.functions.flatMap(check).inSourceOrder
    }

    private static func check(_ function: IRFunction) -> [Diagnostic] {
        // Replay each block from the state it is entered in, recording the errors at its uses and stores.
        var errors = FunctionErrors(function: function)
        let analysis = InitializationAnalysis(function)
        // A block that no path reaches has no entry state, and so no errors.
        for case (let block, var state?) in zip(function.blocks, analysis.entryStates) {
            state.apply(block, use: { errors.use($0, holding: $1) },
                        store: { errors.store(to: $0, holding: $1) })
        }
        return errors.diagnostics
    }
}

/// The errors in one function. Of the uses that the same moves reach, or that no assignment since the local's
/// declaration reaches, only the first in the source is reported, since each of them has the same cause.
private struct FunctionErrors {
    /// Why a local may hold no value at a use: the moves that may have taken its value, or none when nothing may
    /// have assigned it since its declaration.
    private struct Cause: Hashable {
        var local: LocalID
        var moves: Set<SourceRange>
    }

    let function: IRFunction
    private var firstUses: [Cause: Diagnostic] = [:]
    private var stores: [Diagnostic] = []

    init(function: IRFunction) {
        self.function = function
    }

    /// The errors at uses, then those at stores.
    var diagnostics: [Diagnostic] {
        Array(firstUses.values) + stores
    }

    /// Records the error, if there is one, of a use of `place` where its local holds `state`.
    mutating func use(_ place: Place, holding state: LocalState) {
        // A local that holds a value on every path is used without error.
        guard !state.isInitialized else { return }
        // Only a local the source declares can lack a value, since lowering writes a temporary before it reads it.
        guard case .source(let name, _, _) = function.locals[place.local.index] else {
            preconditionFailure("lowering writes a temporary before it reads it, and never moves one")
        }

        let code = useError(naming: name, holding: state)
        keep(Diagnostic(code, at: place.range), for: Cause(local: place.local, moves: state.moves))
    }

    /// Records the error, if there is one, of a store to `place` where its local holds `state`.
    mutating func store(to place: Place, holding state: LocalState) {
        // A store to a `var`, or to a temporary, is never an error.
        guard case .source(let name, .let, _) = function.locals[place.local.index] else { return }
        // A store to a `let` that no path has assigned yet gives it its one value.
        guard state.isAssignedOnSomePath else { return }

        stores.append(Diagnostic(storeError(naming: name, holding: state), at: place.range))
    }

    /// Keeps `diagnostic` as the error of `cause`, unless the one kept for it starts no later in the source.
    private mutating func keep(_ diagnostic: Diagnostic, for cause: Cause) {
        // An error kept already for the cause, at or before this one, stays the cause's only error.
        if let kept = firstUses[cause], kept.range.start <= diagnostic.range.start { return }
        firstUses[cause] = diagnostic
    }

    /// The error for a use of the local `name` where it holds `state`, which leaves it without a value on some path.
    private func useError(naming name: String, holding state: LocalState) -> ErrorCode {
        // Where no move reaches the use, the local was never assigned on some path, or on any.
        if state.moves.isEmpty {
            return state.holdsValueOnSomePath ? .usedMaybeUninitialized(name: name) : .usedUninitialized(name: name)
        }

        // Where a move reaches it, the local was moved from on every path, or only on some.
        let isMovedOnEveryPath = !state.holdsValueOnSomePath && !state.isUnassignedOnSomePath
        return isMovedOnEveryPath ? .usedAfterMove(name: name) : .usedAfterMaybeMove(name: name)
    }

    /// The error for a store to the `let` called `name` where it holds `state`, which has it assigned on some path.
    private func storeError(naming name: String, holding state: LocalState) -> ErrorCode {
        state.isUnassignedOnSomePath ? .letMaybeAssignedTwice(name: name) : .letAssignedTwice(name: name)
    }
}
