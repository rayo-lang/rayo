import RayoIR
import RayoSource

/// What each local of a function, and each place moved out of one, holds at a point.
struct InitializationState: Equatable {
    /// Called with a place that a block uses, or a part of a local it stores to, where the source names it, and why
    /// the place, or the value around the part, may hold no value just before the block does.
    typealias UseVisitor = (Place, SourceRange, MissingValue) -> Void
    /// Called with a whole local that a block stores to, and what the local holds just before the block does.
    typealias StoreVisitor = (Destination, PlaceState) -> Void

    /// Indexed by `LocalID`.
    private var locals: [LocalState]

    /// The state on entry to `body`, where its first `parameterCount` locals, its function's parameters, hold their
    /// arguments, and its other locals hold nothing yet.
    init(entering body: IRBody, parameterCount: Int) {
        locals = body.locals.indices.map { $0 < parameterCount ? .initialized : .declared }
    }

    func joined(with other: InitializationState) -> InitializationState {
        var joined = self
        joined.locals = zip(locals, other.locals).map { $0.joined(with: $1) }
        return joined
    }

    /// Applies what `block` does to the locals. It hands `use` each operand that names a place that may hold no
    /// value, and each statement's destination inside a local that may not hold the rest of its value; it hands
    /// `store` each destination that is a whole local.
    mutating func apply(_ block: BasicBlock, use: UseVisitor = { _, _, _ in }, store: StoreVisitor = { _, _ in }) {
        for statement in block.statements {
            apply(statement, use: use, store: store)
        }
        // The terminator's operand is the block's last use.
        if let operand = block.terminator.operand {
            apply(operand, use: use)
        }
    }

    private mutating func apply(_ statement: Statement, use: UseVisitor, store: StoreVisitor) {
        switch statement {
        // A computation uses its operands, in order, before it stores to its destination.
        case .compute(let destination, let value, _):
            value.operands.forEach { apply($0, use: use) }
            // A computation with no destination drops its value.
            guard let destination else { return }
            assign(destination, use: use, store: store)

        // A declaration leaves the local without a value, even one an earlier pass of a loop gave it.
        case .declare(let local):
            locals[local.index] = .declared
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

    private mutating func apply(_ operand: Operand, use: UseVisitor) {
        switch operand {
        // A constant names no local.
        case .constant:
            break

        // A read uses the place and leaves its value in it.
        case .read(let place, let range):
            visitUse(of: place, at: range, use: use)

        // A move uses the place and takes its value.
        case .move(let place, let range):
            visitUse(of: place, at: range, use: use)
            locals[place.root.index].move(place, at: range)
        }
    }

    /// Hands `use` the place an operand names at `range`, where it may hold no value.
    private func visitUse(of place: Place, at range: SourceRange, use: UseVisitor) {
        // A place that holds its whole value on every path leaves nothing to hand on.
        guard let missing = locals[place.root.index].missingValue(forUseOf: place) else { return }
        use(place, range, missing)
    }
}
