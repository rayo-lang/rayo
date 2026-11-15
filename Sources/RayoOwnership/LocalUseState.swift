import RayoIR
import RayoSema

/// Which locals some later code uses, at a point, before a declaration starts their lives again.
struct LocalUseState: DataflowState {
    private(set) var locals: Set<LocalID> = []

    var direction: DataflowDirection { .backward }

    /// The state at the end of a function, after which no code uses any local.
    init() {}

    func merged(with other: LocalUseState) -> LocalUseState {
        LocalUseState(locals: locals.union(other.locals))
    }

    private init(locals: Set<LocalID>) {
        self.locals = locals
    }

    /// Takes the state across `effect`, where `uses` says which local each effect in the function uses.
    mutating func apply(_ effect: Effect, in uses: LocalUses) {
        switch effect {
        // A declaration starts its local's life, and a retirement ends it, so no code before either uses the life
        // that comes after it.
        case .declare(let local), .retire(let local):
            locals.remove(local)

        case .read, .move, .store, .begin, .use, .end, .exit:
            guard let local = uses.local(usedBy: effect) else { return }
            locals.insert(local)
        }
    }
}
