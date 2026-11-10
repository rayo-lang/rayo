import RayoSema

public struct IRFunction: Equatable, Sendable {
    /// The function's name and parameters, such as `f()`, which no other function of the program has.
    public var name: String
    /// How many parameters the function takes, which are its first locals, in order.
    public var parameterCount: Int
    public var result: RayoType
    /// The locals, indexed by `LocalID`: the function's own locals first, then the temporaries that lowering
    /// adds.
    public var locals: [IRLocal]
    /// The blocks, indexed by `BlockID`; the first is the entry.
    public var blocks: [BasicBlock]

    public init(name: String, parameterCount: Int, result: RayoType, locals: [IRLocal], blocks: [BasicBlock]) {
        self.name = name
        self.parameterCount = parameterCount
        self.result = result
        self.locals = locals
        self.blocks = blocks
    }
}
