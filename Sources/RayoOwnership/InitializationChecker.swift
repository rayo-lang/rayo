import RayoDiagnostics
import RayoIR
import RayoSema
import RayoSource

/// Checks that a program uses each local, and each field inside one, only where it holds a value, and assigns each
/// `let` at most once on each path.
public enum InitializationChecker {
    /// Reports the uses of places that may hold no value, and the assignments to `let`s that may already have been
    /// assigned, in source order.
    public static func check(_ program: IRProgram) -> [Diagnostic] {
        // A use and a store share a place in a compound assignment, which uses the local before it stores to it,
        // so errors at one place keep the order each function gives them.
        program.functions.flatMap { check(PlaceTypes(function: $0, types: program.types)) }.inSourceOrder
    }

    /// Checks the function whose places `places` gives the types of.
    private static func check(_ places: PlaceTypes) -> [Diagnostic] {
        var errors = FunctionErrors(places: places)
        let analysis = InitializationAnalysis(places.function)
        for case (let block, var state?) in zip(places.function.blocks, analysis.entryStates) {
            state.apply(block, use: { errors.use($0, missing: $1) }, store: { errors.store(to: $0, holding: $1) })
        }
        return errors.diagnostics
    }
}

/// The errors in one function. Of the uses that the same moves of a place reach, or that no assignment since the
/// local's declaration reaches, only the first in the source is reported, since each of them has the same cause.
private struct FunctionErrors {
    /// Why a place may hold no value at a use: the moves that may have taken the value of the local, or of the field
    /// at `fields` inside it, or none when nothing may have assigned the local since its declaration.
    private struct Cause: Hashable {
        var local: LocalID
        var fields: [Int]
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

    mutating func use(_ place: Place, missing: MissingValue) {
        let code = switch missing {
        // The place itself, or a place that holds it, may hold no value, and the error names that place.
        case .missing(let fields, let state):
            useError(naming: name(of: place.local, fields: fields), holding: state)
        // A field inside the place may have been moved out of it, so the place can't be used whole.
        case .partlyMoved(let fields, let state):
            partlyMovedError(naming: name(of: place.local, fields: place.fields),
                             movedField: name(of: place.local, fields: fields), holding: state)
        }
        let cause = Cause(local: place.local, fields: missing.fields, moves: missing.state.moves)
        keep(Diagnostic(code, at: place.range), for: cause)
    }

    mutating func store(to place: Place, holding state: PlaceState) {
        guard case .source(let name, .let, _) = places.function.locals[place.local.index] else { return }
        guard state.isAssignedOnSomePath else { return }
        stores.append(Diagnostic(storeError(naming: name, holding: state), at: place.range))
    }

    /// The name of the place that `fields` lead to inside `local`, which an error at a use names.
    private func name(of local: LocalID, fields: [Int]) -> String {
        // An error at a use names a local of the source, since a temporary is written before it is read, and no use
        // of one follows a move out of it.
        guard let name = places.sourceName(of: local, fields: fields) else {
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
