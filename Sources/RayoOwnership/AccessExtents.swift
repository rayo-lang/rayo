import RayoIR

/// Where each access of a function is live: from where it begins through its last use on each path. Where paths join,
/// an access is live if it is live on any of them.
///
/// Each question is about the points of one block: index `i` is just before the statement at `i`, the number of
/// statements is just before the terminator, and the last index is just after it.
struct AccessExtents {
    private let body: IRBody
    /// What code after each point uses, carried backward.
    private let uses: DataflowResults<AccessUseState>

    /// The extents of the accesses of `body`, where `uses` says what code after each of its points uses.
    init(_ body: IRBody, uses: DataflowResults<AccessUseState>) {
        self.body = body
        self.uses = uses
    }

    /// The accesses live at each point of `block`, those that code after the point uses; nil where no path reaches
    /// the block.
    func live(in block: BlockID) -> [Set<AccessID>]? {
        var live = Array(repeating: Set<AccessID>(), count: body.blocks[block.index].statements.count + 2)
        let reached = uses.walk(block) { point, state in
            live[point] = state.accesses.ids
        }
        return reached ? live : nil
    }
}
