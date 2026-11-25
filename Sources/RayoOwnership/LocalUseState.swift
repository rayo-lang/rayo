import RayoCheckedProgram
import RayoIR

/// Which locals some later code uses, at a point, before a declaration starts their lives again.
struct LocalUseState: DataflowState {
    private var locals: LocalSet

    var direction: DataflowDirection { .backward }

    /// The state at the end of `body`, after which no code uses any local.
    init(leaving body: IRBody) {
        locals = LocalSet(localCount: body.locals.count)
    }

    func merged(with other: LocalUseState) -> LocalUseState {
        var merged = self
        merged.locals = locals.union(other.locals)
        return merged
    }

    /// Whether some later code uses `local`.
    func uses(_ local: LocalID) -> Bool {
        locals.contains(local)
    }

    /// The locals that later code uses here and not where `other`, a state in the same function, holds, in the order
    /// of their IDs.
    func localsUsed(notUsedIn other: LocalUseState) -> [LocalID] {
        locals.locals(notIn: other.locals)
    }

    /// Takes the state across `effect`, where `uses` says which local each effect in the function uses.
    mutating func apply(_ effect: Effect, in uses: LocalUses) {
        switch effect {
        // A declaration starts its local's life, and a retirement ends it, so no code before either uses the life
        // that comes after it.
        case .declare(let local), .retire(let local):
            locals.remove(local)

        case .read, .move, .store, .begin, .use, .end, .depend, .exit:
            guard let local = uses.local(usedBy: effect) else { return }
            locals.insert(local)
        }
    }
}
