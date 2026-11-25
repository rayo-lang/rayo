import RayoCheckedProgram

/// The locals of a function that some path to a point retired, with no declaration after it to start them again.
struct RetiredLocals: DataflowState {
    private var retired: LocalSet

    /// The state on entry to `body`, where no local is retired.
    init(entering body: IRBody) {
        retired = LocalSet(localCount: body.locals.count)
    }

    var direction: DataflowDirection { .forward }

    func contains(_ local: LocalID) -> Bool {
        retired.contains(local)
    }

    func merged(with other: RetiredLocals) -> RetiredLocals {
        var merged = self
        merged.retired = retired.union(other.retired)
        return merged
    }

    mutating func apply(_ effect: Effect, in function: Void) {
        switch effect {
        case .declare(let local):
            retired.remove(local)
        case .retire(let local):
            retired.insert(local)
        case .read, .move, .store, .begin, .use, .end, .depend, .exit:
            break
        }
    }
}
