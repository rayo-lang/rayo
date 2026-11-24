import RayoCheckedProgram

/// The local each effect in one body uses: the one whose storage it reads, writes or reaches through an access it
/// holds. A local's life must last through every use of it.
public struct LocalUses {
    /// The access each statement of the body that begins one begins, by its ID.
    private let accesses: [AccessID: Access]

    public init(_ body: IRBody) {
        accesses = body.begunAccesses
    }

    /// The local that `effect` uses, or nil where it uses none. A declaration and a retirement start and end a local's
    /// life, and use none, and leaving the function uses none.
    public func local(usedBy effect: Effect) -> LocalID? {
        switch effect {
        // An access reaches its place until it ends.
        case .use(let id), .end(let id): accessedLocal(of: id)
        // An effect that names a place uses the local that holds it. A dependence marks the value its place holds,
        // which must be alive to hold it.
        case .read, .move, .store, .begin, .depend, .declare, .retire, .exit: effect.place?.root
        }
    }

    /// The local whose storage the access `id` reaches, which the body begins.
    private func accessedLocal(of id: AccessID) -> LocalID {
        guard let access = accesses[id] else { preconditionFailure("a\(id.index) is used, and never begun") }
        return access.place.root
    }
}
