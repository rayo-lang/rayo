/// Checks that each access in one function's body ends once on every path from where it begins, and that nothing uses
/// it after its end, as the IR the ownership stage gives must. An access is held from the statement that begins it
/// until the statement that ends it, and every path into a block holds the same accesses, so each point of a block
/// that a path reaches holds one set of accesses, whichever path reaches it.
struct AccessScopeVerifier {
    private let body: IRBody
    /// The name of the function whose body this is, which a violation names.
    private let function: String

    init(body: IRBody, of function: String) {
        self.body = body
        self.function = function
    }

    /// Throws the first violation found on a walk of the blocks that a path from the entry reaches: a block that
    /// paths enter holding different accesses, an end or a use of an access that isn't held, or a way out of the
    /// function that leaves an access held. A block that no path reaches runs no access, so it can't break the rule.
    func verify() throws(IRViolation) {
        // The accesses held where each block begins, or nil where the walk hasn't reached it yet.
        var entered: [Set<AccessID>?] = Array(repeating: nil, count: body.blocks.count)
        entered[0] = []
        // The walk runs each block in the order it reaches them, breadth first, so the paths into a join usually reach
        // it before it runs, and a difference between them is reported at the join.
        var reached: [(block: BlockID, held: Set<AccessID>)] = [(BlockID(index: 0), [])]
        var next = 0

        while next < reached.count {
            let (block, held) = reached[next]
            next += 1
            let leaving = try accessesHeld(after: block, entering: held)
            for successor in body.blocks[block.index].terminator.successors {
                // A block the walk has reached must be entered holding what it was entered holding before.
                if let before = entered[successor.index] {
                    guard let differing = before.symmetricDifference(leaving).min() else { continue }
                    throw violation("the IR enters bb\(successor.index) holding a\(differing.index) on one path and "
                        + "not on another")
                }
                entered[successor.index] = leaving
                reached.append((successor, leaving))
            }
        }
    }

    /// The accesses held as `block` reaches its terminator, where `held` are those held as it begins. Throws where it
    /// ends or uses an access that isn't held, or leaves the function with one still held.
    private func accessesHeld(after block: BlockID, entering held: Set<AccessID>) throws(IRViolation) -> Set<AccessID> {
        var held = held
        let label = "bb\(block.index)"
        for statement in body.blocks[block.index].statements {
            switch statement {
            case .begin(let id, _):
                held.insert(id)

            // An end ends a held access, which isn't held after it.
            case .end(let id):
                guard held.remove(id) != nil else {
                    throw violation("the IR ends a\(id.index) at \(label), where it isn't held")
                }

            // A call reaches its arguments' places through their accesses, and a dependence keeps its access live,
            // so each uses an access that must be held.
            case .compute(_, let value, _):
                for id in value.accesses where !held.contains(id) { throw unheld(id, at: label) }
            case .depend(_, let id):
                guard held.contains(id) else { throw unheld(id, at: label) }

            case .declare:
                break
            }
        }

        // A way out of the function ends every access first, since nothing after it can.
        if body.blocks[block.index].terminator.successors.isEmpty, let open = held.min() {
            throw violation("the IR leaves the function at \(label) without ending a\(open.index)")
        }
        return held
    }

    /// The violation of a use of the access `id` at the block `label`, where it isn't held.
    private func unheld(_ id: AccessID, at label: String) -> IRViolation {
        violation("the IR uses a\(id.index) at \(label), where it isn't held")
    }

    /// The violation that `message` says, in this function.
    private func violation(_ message: String) -> IRViolation {
        IRViolation(function: function, message: message)
    }
}
