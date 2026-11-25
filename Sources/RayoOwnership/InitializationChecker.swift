import RayoCheckedProgram
import RayoDiagnostics
import RayoIR
import RayoSource

/// Checks that a program uses each local, and each field inside one, only where it holds a value, and assigns each
/// `let` at most once on each path.
enum InitializationChecker {
    /// Reports the uses of places that may hold no value, and the assignments to `let`s that may already have been
    /// assigned, in `places.body`.
    static func errors(in places: PlaceTypes) -> [Diagnostic] {
        // Each crossing of a block replaces what an earlier one found there. The last starts from the state the block
        // settles on, so what it finds is what the settled states give, with no second walk of the blocks. A block
        // that no path reaches is never crossed, and nothing in it is checked.
        let start = InitializationState(entering: places.body)
        var findings = Array(repeating: [Finding](), count: places.body.blocks.count)
        DataflowSolver.solve(from: start, through: places.body, knowing: ()) { block, state, effects in
            findings[block.index] = crossing(effects, with: &state)
        }

        // The findings go to the errors block by block, as a walk of the blocks in order hands them on.
        var errors = FunctionErrors(places: places)
        for finding in findings.joined() {
            errors.record(finding)
        }
        return errors.diagnostics
    }

    /// Takes `state` forward across `effects`, a block's, and gives what its uses and stores may find, in order.
    private static func crossing(_ effects: BlockEffects, with state: inout InitializationState) -> [Finding] {
        var findings: [Finding] = []
        for effect in effects.all {
            state.apply(
                effect, use: { findings.append(.use($0, at: $1, missing: $2)) },
                store: { destination, held in
                    // Most stores are to a local that holds no value yet, which no error reports, so they are left out.
                    if held.isAssignedOnSomePath { findings.append(.store(destination, holding: held)) }
                },
            )
        }
        return findings
    }
}

/// What a use or a store in a block finds that may be an error: a use of a place that may hold no value, or a store
/// to a local that may hold one already.
private enum Finding {
    case use(Place, at: SourceRange, missing: MissingValue)
    case store(Destination, holding: PlaceState)
}

/// The errors in one function. Of the uses that the same moves of a place reach, or that no assignment since the
/// local's declaration reaches, only the first in the source is reported, since each of them has the same cause.
private struct FunctionErrors {
    /// Why a place may hold no value at a use: the moves that may have taken the value of `place`, a local or a part
    /// of one, or none when nothing may have assigned the local since its declaration.
    private struct Cause: Hashable {
        var place: Place
        var moves: Set<SourceRange>
    }

    let places: PlaceTypes
    private var firstUses: [Cause: Diagnostic] = [:]
    private var stores: [Diagnostic] = []

    init(places: PlaceTypes) {
        self.places = places
    }

    /// The errors at uses, then those at stores.
    var diagnostics: [Diagnostic] {
        Array(firstUses.values) + stores
    }

    mutating func record(_ finding: Finding) {
        switch finding {
        case .use(let place, let range, let missing): use(place, at: range, missing: missing)
        case .store(let destination, let state): store(to: destination, holding: state)
        }
    }

    mutating func use(_ place: Place, at range: SourceRange, missing: MissingValue) {
        // The error names the local or part that may hold no value, and says how it leaves the place short.
        let missingName = name(of: missing.place)
        let code = switch missing.kind {
        // The place itself, or a place that holds it, may hold no value, and the error names that place.
        case .placeOrHolder:
            useError(naming: missingName, holding: missing.state)
        // A field inside the place may have been moved out of it, so the place can't be used whole.
        case .insidePlace:
            partlyMovedError(naming: name(of: place), movedField: missingName, holding: missing.state)
        }

        // Of the uses with the same cause, only the first in the source is kept, with the moves that caused it.
        let cause = Cause(place: missing.place, moves: missing.state.moves)
        keep(Diagnostic(code, at: range, labeling: labeledMoves(missing.state)), for: cause)
    }

    mutating func store(to destination: Destination, holding state: PlaceState) {
        // Only a `let`, whether it owns its value or borrows it, is assigned at most once on each path.
        guard case .source(let name, let kind, _, _) = places.body.locals[destination.place.root.index],
              kind == .let || kind == .refLet else { return }
        guard state.isAssignedOnSomePath else { return }
        stores.append(Diagnostic(storeError(naming: name, holding: state), at: destination.range))
    }

    /// The name of `place`, which an error at a use names.
    private func name(of place: Place) -> String {
        // An error at a use names a local of the source, since a temporary is written before it is read, and no use
        // of one follows a move out of it.
        guard let name = places.sourceName(of: place) else {
            preconditionFailure("lowering writes a temporary before it reads it, and never uses one after a move")
        }
        return name
    }

    /// Keeps `diagnostic` as the error of `cause`, unless the one kept for it starts no later in the source.
    private mutating func keep(_ diagnostic: Diagnostic, for cause: Cause) {
        if let kept = firstUses[cause], kept.range.start <= diagnostic.range.start { return }
        firstUses[cause] = diagnostic
    }

    /// The error for a use of the place called `name` where it holds `state`, which leaves it without a value on some
    /// path.
    private func useError(naming name: String, holding state: PlaceState) -> ErrorCode {
        if state.moves.isEmpty {
            return state.holdsValueOnSomePath ? .usedMaybeUninitialized(name: name) : .usedUninitialized(name: name)
        }
        return state.isMovedOnEveryPath ? .usedAfterMove(name: name) : .usedAfterMaybeMove(name: name)
    }

    /// The moves that may have left a place holding `state` without its value, each labeled where it is, in source
    /// order.
    private func labeledMoves(_ state: PlaceState) -> [Diagnostic.LabeledRange] {
        state.moves.sorted { $0.start < $1.start }.map { Diagnostic.LabeledRange(.moved, at: $0) }
    }

    /// The error for a use of the place called `name` whole, where the field called `field` inside it holds `state`,
    /// which a move left without a value on some path.
    private func partlyMovedError(
        naming name: String, movedField field: String, holding state: PlaceState,
    ) -> ErrorCode {
        state.isMovedOnEveryPath
            ? .usedPartlyMoved(name: name, field: field) : .usedMaybePartlyMoved(name: name, field: field)
    }

    /// The error for a store to the `let` called `name` where it holds `state`, which has it assigned on some path.
    private func storeError(naming name: String, holding state: PlaceState) -> ErrorCode {
        state.isUnassignedOnSomePath ? .letMaybeAssignedTwice(name: name) : .letAssignedTwice(name: name)
    }
}
