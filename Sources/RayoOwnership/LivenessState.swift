import RayoIR
import RayoSema

/// Which locals of a function hold a value that some code reads later, at a point.
struct LivenessState: Equatable {
    /// Called with a statement's destination, and whether some code reads the value it stores there.
    typealias StoreVisitor = (Place, _ isRead: Bool) -> Void

    private var live: Set<LocalID> = []

    /// The state at the end of a function, after which no code reads any local.
    init() {}

    /// The state where a path on which `self` holds meets one on which `other` does.
    func union(_ other: LivenessState) -> LivenessState {
        var union = self
        union.live.formUnion(other.live)
        return union
    }

    /// Takes the state after `block` back to the state before it, handing `store` each statement's destination.
    mutating func apply(backwardsThrough block: BasicBlock, store: StoreVisitor = { _, _ in }) {
        // The terminator's operand is the block's last read, so it comes first going backwards.
        if let operand = block.terminator.operand {
            apply(operand)
        }
        for statement in block.statements.reversed() {
            apply(statement, store: store)
        }
    }

    private mutating func apply(_ statement: Statement, store: StoreVisitor) {
        switch statement {
        // A computation reads its operands before it stores to its destination, so going backwards it stores
        // first.
        case .compute(let destination, let value, _):
            // A computation with a destination stores a value in its local.
            if let destination { assign(destination, store: store) }
            value.operands.forEach { apply($0) }

        // A declaration starts its local's life, so no code before it reads a value the local holds after it.
        case .declare(let local):
            live.remove(local)
        }
    }

    /// Hands `store` `destination` and whether some code reads the value stored there, then leaves the local's
    /// value before the store unread by any code after it.
    private mutating func assign(_ destination: Place, store: StoreVisitor) {
        store(destination, live.contains(destination.local))
        live.remove(destination.local)
    }

    private mutating func apply(_ operand: Operand) {
        switch operand {
        // A constant names no local.
        case .constant:
            break

        // A read and a move both read the value the local holds.
        case .read(let place), .move(let place):
            live.insert(place.local)
        }
    }
}
