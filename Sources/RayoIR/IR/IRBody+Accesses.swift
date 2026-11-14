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
}
