public enum Terminator: Sendable {
    case goto(BlockID)
    /// Continues in `then` when the Bool `condition` is true, and in `otherwise` when it is false.
    case branch(Operand, then: BlockID, otherwise: BlockID)
    /// Leaves the function with the operand as its result, or with none when the function returns Void.
    case `return`(Operand?)
    /// Ends a block that no path reaches, such as the end of a function every path through which returns.
    case unreachable

    public var operand: Operand? {
        switch self {
        case .branch(let condition, _, _): return condition
        case .return(let result): return result
        case .goto, .unreachable: return nil
        }
    }

    /// The blocks that a run can continue in.
    public var successors: [BlockID] {
        switch self {
        case .goto(let target): return [target]
        case .branch(_, let then, let otherwise): return [then, otherwise]
        case .return, .unreachable: return []
        }
    }
}
