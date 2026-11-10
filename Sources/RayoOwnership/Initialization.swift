import RayoIR

/// Whether a local holds a value at a point of a function, over all the paths that reach the point.
enum Initialization: Equatable {
    case initialized
    /// Holds a value on some of the paths that reach the point, and none on the others.
    case maybe
    case uninitialized

    /// What a local holds where a path on which it holds `self` joins one on which it holds `other`.
    func joined(with other: Initialization) -> Initialization {
        self == other ? self : .maybe
    }
}

/// What each local of a function holds at a point.
struct InitializationState: Equatable {
    /// Indexed by `LocalID`.
    private var locals: [Initialization]

    /// The state on entry to `function`, where its parameters hold their arguments and its other locals hold
    /// nothing yet.
    init(enteringFunction function: IRFunction) {
        locals = function.locals.indices.map { $0 < function.parameterCount ? .initialized : .uninitialized }
    }

    func joined(with other: InitializationState) -> InitializationState {
        var joined = self
        joined.locals = zip(locals, other.locals).map { $0.joined(with: $1) }
        return joined
    }

    /// Applies what `block` does to the locals, handing `use` each operand that names a local, with what that
    /// local holds just before the block evaluates the operand.
    mutating func apply(_ block: BasicBlock, use: (Place, Initialization) -> Void) {
        for statement in block.statements {
            statement.value.operands.forEach { apply($0, use: use) }
            if let destination = statement.destination { locals[destination.index] = .initialized }
        }
        block.terminator.operand.map { apply($0, use: use) }
    }

    private mutating func apply(_ operand: Operand, use: (Place, Initialization) -> Void) {
        switch operand {
        case .constant:
            break
        case .read(let place):
            use(place, locals[place.local.index])
        case .move(let place):
            use(place, locals[place.local.index])
            locals[place.local.index] = .uninitialized
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
            state.apply(basicBlock) { _, _ in }
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
