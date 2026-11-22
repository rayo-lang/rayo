import RayoCheckedProgram
import RayoIR

/// The accesses that the value each local holds depends on at a point, and those that each access depends on through
/// the place it reaches. A local or an access left out depends on none.
///
/// A value comes to depend on an access only where a dependence says so. A value stored anew depends on nothing, since
/// a value the IR computes, copies or moves carries no dependence of its own: a `ref let`'s value is its one source,
/// and it can't be moved.
struct DependencyState: DataflowState {
    /// The accesses each local's value depends on, by the local's ID, wherever in the local the value lies.
    private var localDependencies: [LocalID: Set<AccessID>] = [:]
    /// The accesses each access depends on, by its ID: those its place's value depended on as it began.
    private var accessDependencies: [AccessID: Set<AccessID>] = [:]

    var direction: DataflowDirection { .forward }

    /// The state on entry to a function, where no value depends on an access, since none has begun.
    init() {}

    func merged(with other: DependencyState) -> DependencyState {
        var merged = self
        merged.localDependencies.merge(other.localDependencies) { $0.union($1) }
        merged.accessDependencies.merge(other.accessDependencies) { $0.union($1) }
        return merged
    }

    /// The accesses that the value `local` holds depends on.
    func dependencies(of local: LocalID) -> Set<AccessID> {
        localDependencies[local] ?? []
    }

    /// The accesses that `access` depends on.
    func dependencies(of access: AccessID) -> Set<AccessID> {
        accessDependencies[access] ?? []
    }

    mutating func apply(_ effect: Effect, in function: Void) {
        switch effect {
        // The value at the place now depends on the access too, and on what the access depends on.
        case .depend(let place, let id):
            localDependencies[place.root, default: []].formUnion(dependencies(of: id).union([id]))

        // An access depends on what its place's value depends on, since the code reaches that value through it.
        case .begin(let id, let access):
            accessDependencies[id] = dependencies(of: access.place.root)

        // A value stored in a whole local replaces the old one and what it depended on; one stored in a part of it
        // leaves what the rest of the local's value depends on.
        case .store(let destination) where destination.place.steps.isEmpty:
            localDependencies[destination.place.root] = nil

        // A declaration starts a local's life without a value, and a retirement ends it, so the local depends on
        // nothing.
        case .declare(let local), .retire(let local):
            localDependencies[local] = nil

        case .read, .move, .store, .use, .end, .exit:
            break
        }
    }
}
