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
        let found = program.functions.flatMap(check).enumerated()
        return found.sorted { ($0.element.range.start, $0.offset) < ($1.element.range.start, $1.offset) }
            .map(\.element)
    }

    private static func check(_ function: IRFunction) -> [Diagnostic] {
        var errors = FunctionErrors(function: function)
        let analysis = InitializationAnalysis(function)
        for (block, entryState) in zip(function.blocks, analysis.entryStates) {
            guard var state = entryState else { continue }
            state.apply(block, use: { errors.use($0, holding: $1) }, store: { errors.store(to: $0, holding: $1) })
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

    mutating func use(_ place: Place, holding state: LocalState) {
        guard let code = useError(place, holding: state) else { return }
        let diagnostic = Diagnostic(code, at: place.range)
        let cause = Cause(local: place.local, moves: state.moves)
        if firstUses[cause].map({ diagnostic.range.start < $0.range.start }) ?? true {
            firstUses[cause] = diagnostic
        }
    }

    mutating func store(to place: Place, holding state: LocalState) {
        guard let code = storeError(place, holding: state) else { return }
        stores.append(Diagnostic(code, at: place.range))
    }

    /// The error for a use of `place` where its local holds `state`, or nil when it holds a value.
    private func useError(_ place: Place, holding state: LocalState) -> ErrorCode? {
        guard !state.isInitialized else { return nil }
        guard let name = function.locals[place.local.index].name else {
            preconditionFailure("lowering moves no temporary, and reads one only once it has written it")
        }
        if state.moves.isEmpty {
            return state.holdsValueOnSomePath ? .usedMaybeUninitialized(name: name) : .usedUninitialized(name: name)
        }
        let isMovedOnEveryPath = !state.holdsValueOnSomePath && !state.isUnassignedOnSomePath
        return isMovedOnEveryPath ? .usedAfterMove(name: name) : .usedAfterMaybeMove(name: name)
    }

    /// The error for a store to `place` where its local holds `state`, or nil when the local may be assigned.
    private func storeError(_ place: Place, holding state: LocalState) -> ErrorCode? {
        let local = function.locals[place.local.index]
        guard local.isLet, state.isAssignedOnSomePath, let name = local.name else { return nil }
        return state.isUnassignedOnSomePath ? .letMaybeAssignedTwice(name: name) : .letAssignedTwice(name: name)
    }
}
