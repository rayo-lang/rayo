import RayoSema

/// The body of a function of the program, as a control-flow graph.
public struct IRBody: Equatable, Sendable {
    /// The locals, indexed by `LocalID`: the body's own locals first, its function's parameters first among them,
    /// then the temporaries that lowering adds.
    public var locals: [IRLocal]
    /// The blocks, indexed by `BlockID`; the first is the entry.
    public var blocks: [BasicBlock]

    public init(locals: [IRLocal], blocks: [BasicBlock]) {
        self.locals = locals
        self.blocks = blocks
    }
}
