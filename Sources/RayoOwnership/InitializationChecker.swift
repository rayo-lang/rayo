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
        let start = InitializationState(entering: places.body)
        let results = DataflowSolver.solve(from: start, through: places.body, knowing: ())
        var errors = FunctionErrors(places: places)
        for (index, block) in places.body.blocks.enumerated() {
            // A block that no path reaches has no state, and nothing in it is checked.
            guard let entry = results.boundaryState(of: BlockID(index: index)) else { continue }
            check(block, from: entry, into: &errors)
        }
        return errors.diagnostics
    }

    /// Hands `errors` what each statement of `block`, and its terminator, may find missing, where the locals hold
    /// `state` on entry to the block. It carries that one state through the block, so no statement copies it.
    private static func check(_ block: BasicBlock, from state: InitializationState, into errors: inout FunctionErrors) {
        var state = state
        block.forEachEffect { effect in
            state.apply(
                effect, use: { errors.use($0, at: $1, missing: $2) }, store: { errors.store(to: $0, holding: $1) },
            )
        }
    }
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
