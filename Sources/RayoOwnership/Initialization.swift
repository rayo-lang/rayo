import RayoIR
import RayoSource

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

/// What each local of a function holds at a point.
struct InitializationState: Equatable {
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
    /// statement's destination, with that local's state just before the block evaluates the operand or stores
    /// the value.
    mutating func apply(_ block: BasicBlock, use: (Place, LocalState) -> Void = { _, _ in },
                        store: (Place, LocalState) -> Void = { _, _ in }) {
        for statement in block.statements {
            switch statement {
            case .compute(let destination, let value, _):
                value.operands.forEach { apply($0, use: use) }
                guard let destination else { continue }
                store(destination, locals[destination.local.index])
                locals[destination.local.index] = .initialized
            case .declare(let local):
                locals[local.index] = .declared
            }
        }
        block.terminator.operand.map { apply($0, use: use) }
    }

    private mutating func apply(_ operand: Operand, use: (Place, LocalState) -> Void) {
        switch operand {
        case .constant:
            break
        case .read(let place):
            use(place, locals[place.local.index])
        case .move(let place):
            use(place, locals[place.local.index])
            locals[place.local.index] = locals[place.local.index].moved(at: place.range)
        }
    }
}

/// The forward data flow of what each local of a function holds, through the function's control-flow graph.
struct InitializationAnalysis {
    /// The state on entry to each block, indexed by `BlockID`; nil for a block that no path from the function's
    /// entry reaches.
    private(set) var entryStates: [InitializationState?]

    init(_ function: IRFunction) {
        entryStates = Array(repeating: nil, count: function.blocks.count)
        entryStates[0] = InitializationState(enteringFunction: function)
        var pending = [BlockID(index: 0)]
        while let block = pending.popLast() {
            // A block is pending only once a state has been joined into its entry.
            var state = entryStates[block.index]!
            let basicBlock = function.blocks[block.index]
            state.apply(basicBlock)
            for successor in basicBlock.terminator.successors {
                if join(state, intoEntryOf: successor) { pending.append(successor) }
            }
        }
    }

    /// Joins `state` into the state on entry to `block`, and returns whether that changed it.
    private mutating func join(_ state: InitializationState, intoEntryOf block: BlockID) -> Bool {
        let joined = entryStates[block.index].map { $0.joined(with: state) } ?? state
        guard joined != entryStates[block.index] else { return false }
        entryStates[block.index] = joined
        return true
    }
}
