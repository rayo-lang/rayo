import RayoIR
import RayoSource

/// What each local of a function, and each place moved out of one, holds at a point.
struct InitializationState: DataflowState {
    /// Called with a place that a statement or terminator uses, or a part of a local it stores to, where the source
    /// names it, and why the place, or the value around the part, may hold no value just before it does.
    typealias UseVisitor = (Place, SourceRange, MissingValue) -> Void
    /// Called with a whole local that a statement stores to, and what the local holds just before it does.
    typealias StoreVisitor = (Destination, PlaceState) -> Void

    /// Indexed by `LocalID`.
    private var locals: [LocalState]

    /// The state on entry to `body`, where its function's parameters hold their arguments, and its other locals hold
    /// nothing yet.
    init(entering body: IRBody) {
        locals = body.locals.map { $0.parameterConvention != nil ? .initialized : .declared }
    }

    func merged(with other: InitializationState) -> InitializationState {
        var merged = self
        merged.locals = zip(locals, other.locals).map { $0.joined(with: $1) }
        return merged
    }

    var direction: DataflowDirection { .forward }

    mutating func apply(_ effect: Effect, in function: Void) {
        apply(effect, use: { _, _, _ in }, store: { _, _ in })
    }

    /// Applies what `effect` does to the locals. On the way, it hands `use` the place that a read, a move or an access
    /// uses where it may hold no value, and the destination of a store where that lies inside a local that may not hold
    /// the rest of its value, and hands `store` the destination of a store where that is a whole local.
    mutating func apply(_ effect: Effect, use: UseVisitor, store: StoreVisitor) {
        switch effect {
        // A read uses the place and leaves its value in it.
        case .read(let place, let range):
            visitUse(of: place, at: range, use: use)

        // A move uses the place and takes its value.
        case .move(let place, let range):
            visitUse(of: place, at: range, use: use)
            locals[place.root.index].move(place, at: range)

        case .store(let destination):
            assign(destination, use: use, store: store)

        // An access uses its place, whose value it reads or changes, and leaves the value there.
        case .begin(_, let access):
            visitUse(of: access.place, at: access.range, use: use)

        // A declaration, or a retirement, leaves the local without a value, even one an earlier pass of a loop gave it.
        case .declare(let local), .retire(let local):
            locals[local.index] = .declared

        // Reaching a place through an access and ending one use only the value that the access's beginning used, and
        // leaving the function uses none.
        case .use, .end, .exit:
            break
        }
    }

    /// Hands `store` the state of `destination` where it is a whole local, or `use` what the part's store may miss
    /// around it, then gives the place a value.
    private mutating func assign(_ destination: Destination, use: UseVisitor, store: StoreVisitor) {
        let place = destination.place
        let local = locals[place.root.index]
        if place.steps.isEmpty {
            // A store to a whole local gives it a value, whatever it held.
            store(destination, local.whole)
        } else if let missing = local.missingValue(forStoreTo: place) {
            // A store to a part changes part of a value that the local must already hold around it.
            use(place, destination.range, missing)
        }
        locals[place.root.index].assign(place)
    }

    /// Hands `use` the place that an effect uses, which the source names at `range`, where it may hold no value.
    private func visitUse(of place: Place, at range: SourceRange, use: UseVisitor) {
        // A place that holds its whole value on every path leaves nothing to hand on.
        guard let missing = locals[place.root.index].missingValue(forUseOf: place) else { return }
        use(place, range, missing)
    }
}
