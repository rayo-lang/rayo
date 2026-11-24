import RayoIR

/// The accesses live at a point: those that some code after it uses, before any statement begins them again.
struct LiveAccesses: DataflowState {
    private(set) var ids: Set<AccessID>

    var direction: DataflowDirection { .backward }

    /// The state at the end of a function, after which no code uses an access.
    init() {
        ids = []
    }

    /// The accesses live where `ids` are.
    private init(_ ids: Set<AccessID>) {
        self.ids = ids
    }

    func merged(with other: LiveAccesses) -> LiveAccesses {
        LiveAccesses(ids.union(other.ids))
    }

    mutating func apply(_ effect: Effect, in function: Void) {
        switch effect {
        // A use reaches the place through the access, and a dependence needs the access live where a value comes to
        // depend on it.
        case .use(let id), .depend(_, let id):
            ids.insert(id)

        // Code before an access begins can't use it, whatever the code after it does.
        case .begin(let id, _):
            ids.remove(id)

        case .read, .move, .store, .end, .declare, .retire, .exit:
            break
        }
    }
}
