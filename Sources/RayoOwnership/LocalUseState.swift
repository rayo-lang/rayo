import RayoIR
import RayoSema

/// Which locals some later code uses, at a point, before a declaration starts their lives again.
struct LocalUseState: DataflowState {
    private(set) var locals: Set<LocalID> = []

    /// The state at the end of a function, after which no code uses any local.
    init() {}

    func merged(with other: LocalUseState) -> LocalUseState {
        LocalUseState(locals: locals.union(other.locals))
    }

    private init(locals: Set<LocalID>) {
        self.locals = locals
    }

    /// Takes the state after `statement` back to the state before it, where `uses` says which locals it uses.
    mutating func apply(backwardsThrough statement: Statement, using uses: LocalUses) {
        switch statement {
        // A declaration starts its local's life, and a retirement ends it, so no code before either uses the life
        // that comes after it.
        case .declare(let local), .retire(let local):
            locals.remove(local)

        case .compute, .begin, .end, .depend:
            locals.formUnion(uses.locals(usedBy: statement))
        }
    }

    /// Takes the state after `terminator` back to the state before it, where `uses` says which locals it uses.
    mutating func apply(backwardsThrough terminator: Terminator, using uses: LocalUses) {
        locals.formUnion(uses.locals(usedBy: terminator))
    }
}
