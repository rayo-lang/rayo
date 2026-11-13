import RayoIR

/// The settled states of a dataflow analysis through a function, which answer what the state is at any point of a
/// block: just before or just after one of its statements, or its terminator, which an index equal to the number of
/// statements names.
struct DataflowResults<Analysis: DataflowAnalysis> {
    /// A point of a block, and the state there.
    private struct Position {
        var block: BlockID
        /// The number of the block's statements, its terminator last among them, that run before the point.
        var point: Int
        var state: Analysis.State
    }

    private let analysis: Analysis
    private let body: IRBody
    /// The settled state at each block's boundary, indexed by `BlockID`: at its entry going forward, and at its exit
    /// going backward. It is nil for a block that no state reaches: one that no path from the entry reaches, and,
    /// going backward, one from which no path reaches an exit.
    private let boundaryStates: [Analysis.State?]
    /// The point asked about last, which the next question about the same block moves on from.
    private var position: Position?

    init(_ analysis: Analysis, in body: IRBody, boundaryStates: [Analysis.State?]) {
        self.analysis = analysis
        self.body = body
        self.boundaryStates = boundaryStates
    }

    /// The state just before the statement at `index` in `block`, or before its terminator where `index` is the
    /// number of statements; nil where no state reaches the block.
    mutating func state(before index: Int, in block: BlockID) -> Analysis.State? {
        state(at: index, in: block)
    }

    /// The state just after the statement at `index` in `block`, or after its terminator where `index` is the
    /// number of statements; nil where no state reaches the block.
    mutating func state(after index: Int, in block: BlockID) -> Analysis.State? {
        state(at: index + 1, in: block)
    }

    /// The state at `point` of `block`, counted as `Position.point` counts it; nil where no state reaches the block.
    private mutating func state(at point: Int, in block: BlockID) -> Analysis.State? {
        guard var position = start(towards: point, in: block) else { return nil }
        let basicBlock = body.blocks[block.index]

        // Apply the effect of each statement between there and `point`, in the analysis's direction.
        while position.point < point {
            analysis.apply(position.point, of: basicBlock, to: &position.state)
            position.point += 1
        }
        while position.point > point {
            position.point -= 1
            analysis.apply(position.point, of: basicBlock, to: &position.state)
        }

        self.position = position
        return position.state
    }

    /// Where a walk to `point` of `block` starts: the last point asked about, where the analysis's direction leads
    /// from it to `point`, and the block's boundary otherwise; nil where no state reaches the block.
    private func start(towards point: Int, in block: BlockID) -> Position? {
        guard let boundaryState = boundaryStates[block.index] else { return nil }

        // A walk goes only in the analysis's direction, so it starts from the last point only where that lies in the
        // block before `point` in that direction.
        if let position, position.block == block {
            switch analysis.direction {
            case .forward where position.point <= point: return position
            case .backward where position.point >= point: return position
            default: break
            }
        }

        let boundary = analysis.direction == .forward ? 0 : body.blocks[block.index].statements.count + 1
        return Position(block: block, point: boundary, state: boundaryState)
    }
}
