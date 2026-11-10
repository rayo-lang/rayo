import RayoIR
import RayoSema

/// What each local of a function holds at a point.
struct InitializationState: Equatable {
    /// Called with a place that a block uses or stores to, and its local's state just before the block does.
    typealias PlaceVisitor = (Place, LocalState) -> Void

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

    /// Applies what `block` does to the locals. It hands `use` each operand that names a local, and `store` each
    /// statement's destination.
    mutating func apply(_ block: BasicBlock, use: PlaceVisitor = { _, _ in }, store: PlaceVisitor = { _, _ in }) {
        for statement in block.statements {
            apply(statement, use: use, store: store)
        }
        // The terminator's operand is the block's last use.
        if let operand = block.terminator.operand {
            apply(operand, use: use)
        }
    }

    private mutating func apply(_ statement: Statement, use: PlaceVisitor, store: PlaceVisitor) {
        switch statement {
        // A computation uses its operands, in order, before it stores to its destination.
        case .compute(let destination, let value, _):
            value.operands.forEach { apply($0, use: use) }
            if let destination { assign(destination, store: store) }

        // A declaration leaves the local without a value, even one an earlier pass of a loop gave it.
        case .declare(let local):
            locals[local.index] = .declared
        }
    }

    /// Hands `store` the state of `destination`'s local, then gives the local a value.
    private mutating func assign(_ destination: Place, store: PlaceVisitor) {
        store(destination, locals[destination.local.index])
        locals[destination.local.index] = .initialized
    }

    private mutating func apply(_ operand: Operand, use: PlaceVisitor) {
        switch operand {
        // A constant names no local.
        case .constant:
            break

        // A read uses the local and leaves its value in it.
        case .read(let place):
            use(place, locals[place.local.index])

        // A move uses the local and takes its value.
        case .move(let place):
            use(place, locals[place.local.index])
            locals[place.local.index] = locals[place.local.index].moved(at: place.range)
        }
    }
}
