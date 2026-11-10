import RayoIR
import RayoSema
import RayoSource

/// The forward data flow of what each local of a function holds, through the function's control-flow graph.
struct InitializationAnalysis {
    /// The state on entry to each block, indexed by `BlockID`; nil for a block that no path from the function's
    /// entry reaches.
    private(set) var entryStates: [InitializationState?]

    /// A state that reaches the entry of `block`, from the function's entry or along an edge.
    private typealias Arrival = (block: BlockID, state: InitializationState)

    init(_ function: IRFunction) {
        entryStates = Array(repeating: nil, count: function.blocks.count)
        var pending: [Arrival] = [(BlockID(index: 0), InitializationState(enteringFunction: function))]
        while let arrival = pending.popLast() {
            pending += flow(arrival, through: function)
        }
    }

    /// Joins `arrival`'s state into the state on entry to its block. When that changes it, returns what the block
    /// hands each of its successors; otherwise none.
    private mutating func flow(_ arrival: Arrival, through function: IRFunction) -> [Arrival] {
        // A state that adds nothing to what the block was entered with already changes nothing after it.
        guard let entryState = join(arrival.state, intoEntryOf: arrival.block) else { return [] }
        let block = function.blocks[arrival.block.index]
        var exitState = entryState
        exitState.apply(block)
        return block.terminator.successors.map { ($0, exitState) }
    }

    /// Joins `state` into the state on entry to `block`, and returns the joined state, or nil when that changed
    /// nothing.
    private mutating func join(_ state: InitializationState, intoEntryOf block: BlockID) -> InitializationState? {
        let joined = entryStates[block.index].map { $0.joined(with: state) } ?? state
        // The state on entry is unchanged.
        guard joined != entryStates[block.index] else { return nil }
        entryStates[block.index] = joined
        return joined
    }
}

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

/// What a local holds at a point of a function. On each path that reaches the point, the local holds a value,
/// holds none because nothing has assigned it since its declaration, or holds none because a move took its value.
struct LocalState: Equatable {
    var holdsValueOnSomePath: Bool
    var isUnassignedOnSomePath: Bool
    /// The ranges of the moves after which no assignment gives the local a value on some path to the point.
    /// Lowering gives each move a range of its own.
    var moves: Set<SourceRange>

    static let initialized = LocalState(holdsValueOnSomePath: true, isUnassignedOnSomePath: false, moves: [])
    static let declared = LocalState(holdsValueOnSomePath: false, isUnassignedOnSomePath: true, moves: [])

    /// The state after the move at `range`, which takes the local's value on the paths where it holds one.
    func moved(at range: SourceRange) -> LocalState {
        LocalState(holdsValueOnSomePath: false, isUnassignedOnSomePath: isUnassignedOnSomePath,
                   moves: holdsValueOnSomePath ? moves.union([range]) : moves)
    }

    /// Whether the local holds a value on every path.
    var isInitialized: Bool {
        !isUnassignedOnSomePath && moves.isEmpty
    }

    /// Whether an assignment has given the local a value on some path, though a move may have taken it since.
    var isAssignedOnSomePath: Bool {
        holdsValueOnSomePath || !moves.isEmpty
    }

    /// What a local holds where a path on which it holds `self` joins one on which it holds `other`.
    func joined(with other: LocalState) -> LocalState {
        LocalState(holdsValueOnSomePath: holdsValueOnSomePath || other.holdsValueOnSomePath,
                   isUnassignedOnSomePath: isUnassignedOnSomePath || other.isUnassignedOnSomePath,
                   moves: moves.union(other.moves))
    }
}
