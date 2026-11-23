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
        let tracked = TrackedPlaces(places.body)
        let start = InitializationState(entering: places.body, tracking: tracked)
        let transfer = InitializationTransfer(places.body, tracking: tracked)
        let results = DataflowSolver.solve(from: start, through: places.body, knowing: transfer)
        let walk = Walk(places.body, settledOn: results, tracking: tracked)
        guard !walk.findings.isEmpty else { return [] }

        // The moves behind each error are found only once an error needs them.
        let isReached = places.body.blocks.indices.map { results.boundaryState(of: BlockID(index: $0)) != nil }
        let moves = ReachingMoves(places.body, isReached: isReached, takingMoves: walk.takingMoves)
        var errors = FunctionErrors(places: places)
        for finding in walk.findings {
            switch finding {
            case .use(let place, let range, let missing, let point):
                errors.use(place, at: range, missing: missing, moves: moves.moves(of: missing.place, reaching: point))
            case .store(let destination, let isUnassignedOnSomePath):
                errors.store(to: destination, unassignedOnSomePath: isUnassignedOnSomePath)
            }
        }
        return errors.diagnostics
    }
}

/// What a walk of each reached block of a body finds in the settled states, in the order of the blocks and their
/// effects.
private struct Walk {
    /// A use or a store that may be wrong, depending on what the paths to it left in its place.
    enum Finding {
        /// A use of a place, or a store to a part of a local, where the place, or the value around the part, may hold
        /// no value.
        case use(Place, at: SourceRange, missing: MissingValue, before: EffectPoint)
        /// A store to a whole local that some path to it has assigned before.
        case store(Destination, isUnassignedOnSomePath: Bool)
    }

    private(set) var findings: [Finding] = []
    /// The moves before which the moved place holds a value on some path.
    private(set) var takingMoves: Set<EffectPoint> = []

    init(_ body: IRBody, settledOn results: DataflowResults<InitializationState>, tracking places: TrackedPlaces) {
        for (index, block) in body.blocks.enumerated() {
            // A block that no path reaches has no state, and nothing in it is checked.
            let id = BlockID(index: index)
            guard var state = results.boundaryState(of: id) else { continue }
            for (ordinal, effect) in block.effects.joined().enumerated() {
                record(effect, before: EffectPoint(block: id, ordinal: ordinal), in: state, among: places)
                state.apply(effect, among: places)
            }
        }
    }

    /// Records what `effect` may find wrong where the places hold `state` just before it.
    private mutating func record(
        _ effect: Effect, before point: EffectPoint, in state: InitializationState, among places: TrackedPlaces,
    ) {
        switch effect {
        // A read uses the place and leaves its value in it.
        case .read(let place, let range):
            recordUse(of: place, at: range, before: point, in: state, among: places)

        // An access uses its place, whose value it reads or changes.
        case .begin(_, let access):
            recordUse(of: access.place, at: access.range, before: point, in: state, among: places)

        // A move uses the place, and takes its value where some path leaves one there.
        case .move(let place, let range):
            recordUse(of: place, at: range, before: point, in: state, among: places)
            guard let number = places.number(of: place) else { preconditionFailure("every moved place is tracked") }
            if state.holds(.holdsValue, of: number) { takingMoves.insert(point) }

        // A store to a whole local gives it a value, whatever it held. A store to a part changes part of a value that
        // the local must already hold around it.
        case .store(let destination):
            let local = destination.place.root
            if destination.place.steps.isEmpty {
                guard state.holds(.assigned, of: local.index) else { return }
                findings.append(.store(destination, isUnassignedOnSomePath: state.holds(.unassigned, of: local.index)))
            } else if let missing = state.missingValue(forStoreTo: destination.place, among: places) {
                findings.append(.use(destination.place, at: destination.range, missing: missing, before: point))
            }

        // Reaching a place through an access and ending one use only the value that the access's beginning used, a
        // dependence leaves its place's value as it is, and a declaration, a retirement or leaving the function uses
        // none.
        case .use, .end, .depend, .declare, .retire, .exit:
            break
        }
    }

    private mutating func recordUse(
        of place: Place, at range: SourceRange, before point: EffectPoint, in state: InitializationState,
        among places: TrackedPlaces,
    ) {
        // A place that holds its whole value on every path leaves nothing to record.
        guard let missing = state.missingValue(forUseOf: place, among: places) else { return }
        findings.append(.use(place, at: range, missing: missing, before: point))
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

    /// Reports a use of `place` where `missing` may hold no value, and where `moves` may have taken that value.
    mutating func use(_ place: Place, at range: SourceRange, missing: MissingValue, moves: Set<SourceRange>) {
        let state = PlaceState(
            holdsValueOnSomePath: missing.holdsValueOnSomePath, isUnassignedOnSomePath: missing.isUnassignedOnSomePath,
            moves: moves,
        )

        // The error names the local or part that may hold no value, and says how it leaves the place short.
        let missingName = name(of: missing.place)
        let code = switch missing.kind {
        // The place itself, or a place that holds it, may hold no value, and the error names that place.
        case .placeOrHolder:
            useError(naming: missingName, holding: state)
        // A field inside the place may have been moved out of it, so the place can't be used whole.
        case .insidePlace:
            partlyMovedError(naming: name(of: place), movedField: missingName, holding: state)
        }

        // Of the uses with the same cause, only the first in the source is kept, with the moves that caused it.
        let cause = Cause(place: missing.place, moves: moves)
        keep(Diagnostic(code, at: range, labeling: labeledMoves(state)), for: cause)
    }

    /// Reports a store to a whole local that some path to it has assigned, where it is a `let`.
    mutating func store(to destination: Destination, unassignedOnSomePath: Bool) {
        // Only a `let`, whether it owns its value or borrows it, is assigned at most once on each path.
        guard case .source(let name, let kind, _, _) = places.body.locals[destination.place.root.index],
              kind == .let || kind == .refLet else { return }
        let code = storeError(naming: name, unassignedOnSomePath: unassignedOnSomePath)
        stores.append(Diagnostic(code, at: destination.range))
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

    /// The error for a store to the `let` called `name`, which some path has assigned, and some path may not have.
    private func storeError(naming name: String, unassignedOnSomePath: Bool) -> ErrorCode {
        unassignedOnSomePath ? .letMaybeAssignedTwice(name: name) : .letAssignedTwice(name: name)
    }
}
