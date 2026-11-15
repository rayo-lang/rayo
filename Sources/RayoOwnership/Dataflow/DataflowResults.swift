import RayoIR

/// The settled states of a dataflow analysis through a function. They answer what the state is at each point of a
/// block: point `i` lies just before the statement at `i`, the point at the number of statements just before the
/// terminator, and the point one past that just after it.
struct DataflowResults<Analysis: DataflowAnalysis> {
    private let analysis: Analysis
    private let body: IRBody
    /// The settled state at each block's boundary, indexed by `BlockID`: at its entry going forward, and at its exit
    /// going backward. It is nil for a block that no path from the entry reaches.
    private let boundaryStates: [Analysis.State?]

    init(_ analysis: Analysis, in body: IRBody, boundaryStates: [Analysis.State?]) {
        self.analysis = analysis
        self.body = body
        self.boundaryStates = boundaryStates
    }

    /// The settled state at `block`'s boundary: at its entry going forward, and at its exit going backward; nil where
    /// no state reaches the block.
    func boundaryState(of block: BlockID) -> Analysis.State? {
        boundaryStates[block.index]
    }

    /// Walks `block` from its boundary in the analysis's direction, and lends `visit` the state at each point in turn,
    /// with the point. Returns whether a state reaches the block; where none does, it visits no point.
    ///
    /// The walk changes one state in place as it crosses each statement. So `visit` keeps only what it works out from
    /// a state, never the state itself, or the next statement would copy the whole of it.
    @discardableResult
    func walk(_ block: BlockID, visit: (_ point: Int, _ state: Analysis.State) -> Void) -> Bool {
        guard var state = boundaryStates[block.index] else { return false }
        let basicBlock = body.blocks[block.index]
        // The statements, then the terminator, each crossed from the point before it to the point after it.
        let crossings = 0...basicBlock.statements.count

        switch analysis.direction {
        case .forward:
            for index in crossings {
                visit(index, state)
                analysis.apply(index, of: basicBlock, to: &state)
            }
            visit(crossings.upperBound + 1, state)

        case .backward:
            for index in crossings.reversed() {
                visit(index + 1, state)
                analysis.apply(index, of: basicBlock, to: &state)
            }
            visit(0, state)
        }
        return true
    }
}
