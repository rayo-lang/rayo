import RayoSema

/// Lowers one function's body, statements and expressions alike, into its control-flow graph, and makes the IR
/// function of it.
struct FunctionLowering: ~Copyable {
    /// The blocks that a `continue` and a `break` in a loop's body go to.
    struct Loop {
        var header: BlockID
        var exit: BlockID
    }

    var builder: FunctionBuilder
    /// The loops around the code being lowered, innermost last.
    var loops: [Loop] = []

    init(builder: consuming FunctionBuilder) {
        self.builder = builder
    }

    /// Makes the IR function of `checked`, whose body is the statements lowered so far.
    consuming func function(of checked: CheckedFunction) -> IRFunction {
        // End the last block, which a run reaches only in a Void function: the checker makes others return first.
        builder.end(with: checked.result == .void ? .return(nil) : .unreachable)
        return builder.function(of: checked)
    }
}
