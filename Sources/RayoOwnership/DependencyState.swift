import RayoCheckedProgram
import RayoIR

/// The accesses that the value each local holds depends on at a point, and those that each access depends on through
/// the place it reaches.
///
/// A value comes to depend on an access only where a dependence says so. A value stored anew depends on nothing, since
/// a value the IR computes, copies or moves carries no dependence of its own: a `ref let`'s value is its one source,
/// and it can't be moved.
struct DependencyState: DataflowState {
    /// The accesses each local's value depends on, indexed by `LocalID`, wherever in the local the value lies. Blocks
    /// change few locals, so their states share the rest.
    private var localDependencies: PersistentArray<Set<AccessID>>
    /// The accesses each access depends on, indexed by `AccessID`: those its place's value depended on as it began.
    private var accessDependencies: PersistentArray<Set<AccessID>>

    var direction: DataflowDirection { .forward }

    /// The state on entry to `body`, which numbers its accesses below `accessCount`. No value depends on an access
    /// there, since none has begun.
    init(entering body: IRBody, accessCount: Int) {
        localDependencies = PersistentArray(Array(repeating: [], count: body.locals.count))
        accessDependencies = PersistentArray(Array(repeating: [], count: accessCount))
    }

    func merged(with other: DependencyState) -> DependencyState {
        var merged = self
        merged.localDependencies = localDependencies.merged(with: other.localDependencies) { $0.union($1) }
        merged.accessDependencies = accessDependencies.merged(with: other.accessDependencies) { $0.union($1) }
        return merged
    }

    /// The accesses that the value `local` holds depends on.
    func dependencies(of local: LocalID) -> Set<AccessID> {
        localDependencies[local.index]
    }

    /// The accesses that `access` depends on.
    func dependencies(of access: AccessID) -> Set<AccessID> {
        accessDependencies[access.index]
    }

    /// The slots of the arrays' nodes that this state doesn't share with `other`, which a merge of the two reads.
    /// Tests count them to see how the state's cost grows.
    func unsharedSlots(comparedWith other: DependencyState) -> Int {
        localDependencies.unsharedSlots(comparedWith: other.localDependencies)
            + accessDependencies.unsharedSlots(comparedWith: other.accessDependencies)
    }

    mutating func apply(_ effect: Effect, in function: Void) {
        switch effect {
        // The value at the place now depends on the access too, and on what the access depends on.
        case .depend(let place, let id):
            localDependencies[place.root.index].formUnion(dependencies(of: id).union([id]))

        // An access depends on what its place's value depends on, since the code reaches that value through it.
        case .begin(let id, let access):
            accessDependencies[id.index] = dependencies(of: access.place.root)

        // A value stored in a whole local replaces the old one and what it depended on; one stored in a part of it
        // leaves what the rest of the local's value depends on.
        case .store(let destination) where destination.place.steps.isEmpty:
            localDependencies[destination.place.root.index] = []

        // A declaration starts a local's life without a value, and a retirement ends it, so the local depends on
        // nothing.
        case .declare(let local), .retire(let local):
            localDependencies[local.index] = []

        case .read, .move, .store, .use, .end, .exit:
            break
        }
    }
}
