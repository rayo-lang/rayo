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

    /// Throws the first use of a retired local, in the order of the blocks and of the effects in each. A block that no
    /// path from the entry reaches runs nothing, so it can't use a retired local.
    func verify() throws(IRViolation) {
        let retired = DataflowSolver.solve(from: RetiredLocals(entering: body), through: body, knowing: ())
        for index in body.blocks.indices {
            let block = BlockID(index: index)
            guard let entered = retired.boundaryState(of: block) else { continue }
            try verifyUses(in: block, entering: entered)
        }
    }

    /// Throws where `block`, entered with the locals `retired` retired, uses one that is retired where it uses it.
    private func verifyUses(in block: BlockID, entering retired: RetiredLocals) throws(IRViolation) {
        var retired = retired
        for effect in body.blocks[block.index].effects.joined() {
            if let used = uses.local(usedBy: effect), retired.contains(used) {
                let message = "the IR uses %\(used.index) at bb\(block.index), where it is retired"
                throw IRViolation(function: function, message: message)
            }
            retired.apply(effect, in: ())
        }
    }
}
