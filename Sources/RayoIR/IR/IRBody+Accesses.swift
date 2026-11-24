extension IRBody {
    /// The access each statement that begins one begins, by its ID.
    public var begunAccesses: [AccessID: Access] {
        var accesses: [AccessID: Access] = [:]
        for block in blocks {
            for case .begin(let id, let access) in block.statements {
                accesses[id] = access
            }
        }
        return accesses
    }

    /// How many IDs span every access the body begins: one more than the highest of them, so that a table of that
    /// many entries has one for each access.
    package var accessCount: Int {
        let highestID = begunAccesses.keys.max()
        return highestID.map { $0.index + 1 } ?? 0
    }
}
