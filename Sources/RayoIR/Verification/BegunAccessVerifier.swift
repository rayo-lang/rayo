/// Checks that one statement begins each access in one function's body, ahead of each use of it in the order of the
/// blocks and on every path to it. The emitter walks the blocks in that order, and keeps the one address it finds
/// where an access begins.
struct BegunAccessVerifier {
    private let body: IRBody
    /// The name of the function whose body this is, which a violation names.
    private let function: String

    init(body: IRBody, of function: String) {
        self.body = body
        self.function = function
    }

    /// Throws the first violation of the order of the blocks, or else the first on a path, each in the order of the
    /// blocks and of the statements in each.
    func verify() throws(IRViolation) {
        // A use in the block that begins its access follows the beginning on every path, so the paths are walked
        // only for a body that uses an access in another block, which few do.
        let usesAccessOutsideItsBlock = try verifyBlockOrder()
        guard usesAccessOutsideItsBlock else { return }
        try verifyPaths()
    }

    /// Throws at an access that a second statement begins, or that a statement uses before the walk reaches its
    /// beginning. Returns whether some statement uses an access that another block begins.
    private func verifyBlockOrder() throws(IRViolation) -> Bool {
        // The index of the block that begins each access the walk has reached. The walk takes every block, since the
        // emitter emits a block whether or not a path reaches it, and reads each statement in place, since every
        // build runs it on every body.
        var beginningBlocks: [AccessID: Int] = [:]
        var usesOutside = false

        for (index, block) in body.blocks.enumerated() {
            for statement in block.statements {
                if case .begin(let id, _) = statement, beginningBlocks.updateValue(index, forKey: id) != nil {
                    throw violation("the IR begins a\(id.index) at bb\(index), after another statement that begins it")
                }
                for used in Self.accesses(usedBy: statement) {
                    guard let beginningBlock = beginningBlocks[used] else {
                        throw violation("the IR uses a\(used.index) at bb\(index), before its beginning in the order "
                            + "of the blocks")
                    }
                    if beginningBlock != index { usesOutside = true }
                }
            }
        }
        return usesOutside
    }

    /// Throws at an effect that uses an access some path to it hasn't begun, where the address the emitter keeps
    /// isn't worked out. A block that no path from the entry reaches runs nothing, so it needs no address.
    private func verifyPaths() throws(IRViolation) {
        let entry = UnbegunAccessState(accessCount: body.accessCount)
        let settled = DataflowSolver.solve(from: entry, through: body, knowing: ())
        for index in body.blocks.indices {
            try settled.walkEffects(of: BlockID(index: index)) { effect, unbegun throws(IRViolation) in
                guard let used = Self.access(usedBy: effect), unbegun.contains(used) else { return }
                throw violation("the IR uses a\(used.index) at bb\(index), which a path reaches without beginning it")
            }
        }
    }

    /// The accesses that `statement` needs begun: those a call passes, or the one it makes a value depend on. They
    /// are the accesses its effects use or depend on, and a terminator's effects name none.
    private static func accesses(usedBy statement: Statement) -> [AccessID] {
        switch statement {
        case .compute(_, let value, _): value.accesses
        case .depend(_, let id): [id]
        case .begin, .end, .declare, .retire: []
        }
    }

    /// The access that `effect` needs begun: the one it reaches a place through, or makes a value depend on.
    private static func access(usedBy effect: Effect) -> AccessID? {
        switch effect {
        case .use(let id), .depend(_, let id): id
        case .read, .move, .store, .begin, .end, .declare, .retire, .exit: nil
        }
    }

    /// The violation that `message` says, in this function.
    private func violation(_ message: String) -> IRViolation {
        IRViolation(function: function, message: message)
    }
}
