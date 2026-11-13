import RayoIR

/// A question about each point of a function, such as what each local holds there, that a walk through the
/// function's control-flow graph answers. The analysis says where the walk begins and how each statement and
/// terminator changes its state, and `DataflowSolver` carries the state through the blocks.
protocol DataflowAnalysis {
    associatedtype State: DataflowState

    var direction: DataflowDirection { get }

    /// The state where the walk begins: on entry to the function going forward, and at each of its exits going
    /// backward.
    var startState: State { get }

    /// Takes `state` across `statement` in the analysis's direction: from just before it to just after it going
    /// forward, and from just after it to just before it going backward.
    func apply(_ statement: Statement, to state: inout State)

    /// Takes `state` across `terminator`, as `apply(_:to:)` takes it across a statement.
    func apply(_ terminator: Terminator, to state: inout State)
}

extension DataflowAnalysis {
    /// Takes `state` across the statement at `index` in `block`, or across its terminator where `index` is the
    /// number of statements.
    func apply(_ index: Int, of block: BasicBlock, to state: inout State) {
        if index < block.statements.count {
            apply(block.statements[index], to: &state)
        } else {
            apply(block.terminator, to: &state)
        }
    }

    /// Takes `state` across all of `block` in the analysis's direction: from its entry to its exit going forward,
    /// and from its exit to its entry going backward.
    func apply(across block: BasicBlock, to state: inout State) {
        let indices = 0...block.statements.count
        let ordered = direction == .forward ? Array(indices) : indices.reversed()
        for index in ordered {
            apply(index, of: block, to: &state)
        }
    }
}
