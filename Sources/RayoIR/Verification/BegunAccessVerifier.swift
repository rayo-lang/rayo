/// Checks that one function's body begins each access before the emitter needs its address. The emitter walks the
/// blocks in the order of their indices, and keeps one address for each access, found where the access begins, for
/// every use of it. So one statement begins each access, ahead of each use in that order and on every path to it.
struct BegunAccessVerifier {
    private let body: IRBody
    /// The name of the function whose body this is, which a violation names.
    private let function: String

    init(body: IRBody, of function: String) {
        self.body = body
        self.function = function
    }

    /// Throws the first violation of the order of the blocks, or else the first on a path, each in the order of the
    /// blocks and of the effects in each.
    func verify() throws(IRViolation) {
        try verifyBlockOrder()
        try verifyPaths()
    }

    /// Throws at an access that a second statement begins, or that an effect uses before the walk reaches its
    /// beginning. The walk takes every block, since the emitter emits a block whether or not a path reaches it.
    private func verifyBlockOrder() throws(IRViolation) {
        var begun: Set<AccessID> = []
        for (index, block) in body.blocks.enumerated() {
            for effect in block.effects.joined() {
                if case .begin(let id, _) = effect, !begun.insert(id).inserted {
                    throw violation("the IR begins a\(id.index) at bb\(index), after another statement that begins it")
                }
                if let used = Self.access(usedBy: effect), !begun.contains(used) {
                    let use = "the IR uses a\(used.index) at bb\(index)"
                    throw violation("\(use), before its beginning in the order of the blocks")
                }
            }
        }
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
