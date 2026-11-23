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
        try verify(from: RetiredLocals(entering: body))
    }

    /// Verifies as `verify()` does, carrying `start`, which retires no local, through the body. It takes any such
    /// state, so that one which counts its work can measure the check's.
    func verify<Retired: RetiredLocalSet>(from start: Retired) throws(IRViolation) {
        let settled = DataflowSolver.solve(from: start, through: body, knowing: ())
        for index in body.blocks.indices {
            try settled.walkEffects(of: BlockID(index: index)) { effect, retired throws(IRViolation) in
                try verify(effect, at: index, isNotUsing: retired)
            }
        }
    }

    /// Throws where `effect`, in the block at `index`, uses one of the locals `retired`.
    private func verify(
        _ effect: Effect, at index: Int, isNotUsing retired: some RetiredLocalSet,
    ) throws(IRViolation) {
        guard let used = uses.local(usedBy: effect), retired.contains(used) else { return }
        throw IRViolation(function: function, message: "the IR uses %\(used.index) at bb\(index), where it is retired")
    }
}
