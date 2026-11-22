import RayoCheckedProgram

/// Checks that nothing in one function's body uses a local on any path after a retirement ends its life, until a
/// declaration starts it again, as the IR the ownership stage gives must. Paths into a block may differ in which locals
/// they retired, so a block is entered with each local retired on any path into it.
struct LocalLifeVerifier {
    private let body: IRBody
    /// The name of the function whose body this is, which a violation names.
    private let function: String
    private let uses: LocalUses

    init(body: IRBody, of function: String) {
        self.body = body
        self.function = function
        uses = LocalUses(body)
    }

    /// Throws the first use found of a retired local, on a walk of the blocks that a path from the entry reaches. A
    /// block that no path reaches runs nothing, so it can't use a retired local.
    func verify() throws(IRViolation) {
        // The locals retired on some path into each block, or nil where the walk hasn't reached it yet.
        var entered: [Set<LocalID>?] = Array(repeating: nil, count: body.blocks.count)
        entered[0] = []

        // A block is walked again whenever a path into it brings a local retired that no path walked before brought.
        // Each walk only grows a block's set, so the walk stops.
        var pending = [BlockID(index: 0)]
        while let block = pending.popLast() {
            let leaving = try localsRetired(after: block, entering: entered[block.index] ?? [])
            for successor in body.blocks[block.index].terminator.successors {
                let merged = (entered[successor.index] ?? []).union(leaving)
                guard merged != entered[successor.index] else { continue }
                entered[successor.index] = merged
                pending.append(successor)
            }
        }
    }

    /// The locals retired as `block` ends, where `retired` are those retired as it begins. Throws where it uses one
    /// that is retired.
    private func localsRetired(
        after block: BlockID, entering retired: Set<LocalID>,
    ) throws(IRViolation) -> Set<LocalID> {
        var retired = retired
        let label = "bb\(block.index)"
        for effect in body.blocks[block.index].effects.joined() {
            switch effect {
            case .declare(let local):
                retired.remove(local)
            case .retire(let local):
                retired.insert(local)
            case .read, .move, .store, .begin, .use, .end, .depend, .exit:
                guard let used = uses.local(usedBy: effect) else { continue }
                try verify(used, isNotIn: retired, at: label)
            }
        }
        return retired
    }

    /// Throws where `used`, a local that the block `label` uses, is retired.
    private func verify(_ used: LocalID, isNotIn retired: Set<LocalID>, at label: String) throws(IRViolation) {
        guard retired.contains(used) else { return }
        throw IRViolation(function: function, message: "the IR uses %\(used.index) at \(label), where it is retired")
    }
}
