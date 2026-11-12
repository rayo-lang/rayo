import RayoIR

/// What each local of a function, and each field moved out of one, holds at a point.
struct InitializationState: Equatable {
    /// Called with a place that a block uses, or a field it stores to, and why the place, or the value around the
    /// field, may hold no value just before the block does.
    typealias UseVisitor = (Place, MissingValue) -> Void
    /// Called with a whole local that a block stores to, and what the local holds just before the block does.
    typealias StoreVisitor = (Place, PlaceState) -> Void

    /// Indexed by `LocalID`.
    private var locals: [LocalState]

    /// The state on entry to `function`, where its parameters hold their arguments and its other locals hold
    /// nothing yet.
    init(enteringFunction function: IRFunction) {
        locals = function.locals.indices.map { $0 < function.parameterCount ? .initialized : .declared }
    }

    func joined(with other: InitializationState) -> InitializationState {
        var joined = self
        joined.locals = zip(locals, other.locals).map { $0.joined(with: $1) }
        return joined
    }

    /// Applies what `block` does to the locals. It hands `use` each operand that names a place that may hold no
    /// value, and each statement's destination inside a local that may not hold the rest of its value; it hands
    /// `store` each destination that is a whole local.
    mutating func apply(_ block: BasicBlock, use: UseVisitor = { _, _ in }, store: StoreVisitor = { _, _ in }) {
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

    /// Hands `store` the state of `destination` where it is a whole local, or `use` what the field's store may miss
    /// around it, then gives the place a value.
    private mutating func assign(_ destination: Place, use: UseVisitor, store: StoreVisitor) {
        let local = locals[destination.local.index]
        if destination.fields.isEmpty {
            // A store to a whole local gives it a value, whatever it held.
            store(destination, local.whole)
        } else if let missing = local.missingValue(forStoreTo: destination.fields) {
            // A store to a field changes part of a value that the local must already hold around it.
            use(destination, missing)
        }
        locals[destination.local.index].assign(destination.fields)
    }

    private mutating func apply(_ operand: Operand, use: UseVisitor) {
        switch operand {
        // A constant names no local.
        case .constant:
            break

        // A read uses the place and leaves its value in it.
        case .read(let place):
            visitUse(of: place, use: use)

        // A move uses the place and takes its value.
        case .move(let place):
            visitUse(of: place, use: use)
            locals[place.local.index].move(place.fields, at: place.range)
        }
    }

    /// Hands `use` the place an operand names, where it may hold no value.
    private func visitUse(of place: Place, use: UseVisitor) {
        // A place that holds its whole value on every path leaves nothing to hand on.
        guard let missing = locals[place.local.index].missingValue(forUseOf: place.fields) else { return }
        use(place, missing)
    }
}
