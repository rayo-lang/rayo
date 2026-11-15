import RayoSema

/// The locals each statement and terminator of one body uses: those whose storage it reads, writes or reaches through
/// an access it holds, and those that hold the indices it finds elements by. A local's life must last through every
/// use of it.
public struct LocalUses {
    /// The access each statement of the body that begins one begins, by its ID.
    private let accesses: [AccessID: Access]

    public init(_ body: IRBody) {
        accesses = body.begunAccesses
    }

    /// The locals `statement` uses. A declaration and a retirement start and end a local's life, and use none.
    public func locals(usedBy statement: Statement) -> [LocalID] {
        switch statement {
        case .compute(let destination, let value, _):
            locals(storingIn: destination, computing: value)

        // An access finds its place where it begins, and reaches it until it ends.
        case .begin(_, let access):
            Self.locals(of: access.place)
        case .end(let id):
            [accessedLocal(of: id)]

        // A dependence ties the value at its place to the access, whose place must outlast the value's uses.
        case .depend(let place, let id):
            Self.locals(of: place) + [accessedLocal(of: id)]

        case .declare, .retire:
            []
        }
    }

    /// The locals `terminator` uses: those its operand reads or moves.
    public func locals(usedBy terminator: Terminator) -> [LocalID] {
        terminator.operand.map(Self.locals) ?? []
    }

    /// The locals a computation of `value` uses: those of `destination`, where it has one, which it stores to, those of
    /// its operands, which it reads, and the local each access a call passes reaches.
    private func locals(storingIn destination: Destination?, computing value: Rvalue) -> [LocalID] {
        let stored = destination.map { Self.locals(of: $0.place) } ?? []
        let read = value.operands.flatMap(Self.locals)
        return stored + read + value.accesses.map(accessedLocal)
    }

    /// The locals that finding `place` and reaching it use: its root, and those that hold its indices.
    private static func locals(of place: Place) -> [LocalID] {
        [place.root] + place.indexLocals
    }

    /// The locals that `operand` uses: none for a constant, and those of the place it reads or moves otherwise.
    private static func locals(of operand: Operand) -> [LocalID] {
        operand.place.map(locals) ?? []
    }

    /// The local whose storage the access `id` reaches, which the body begins.
    private func accessedLocal(of id: AccessID) -> LocalID {
        guard let access = accesses[id] else { preconditionFailure("a\(id.index) is used, and never begun") }
        return access.place.root
    }
}
