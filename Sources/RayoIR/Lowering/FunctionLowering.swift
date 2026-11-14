import RayoSema

/// Lowers one function's body, statements and expressions alike, into its control-flow graph, and makes the IR
/// body of it.
struct FunctionLowering: ~Copyable {
    /// The blocks that a `continue` and a `break` in a loop's body go to.
    struct Loop {
        var header: BlockID
        var exit: BlockID
    }

    var builder: FunctionBuilder
    /// The program's functions, whose declarations say what a call does with its arguments.
    let functions: FunctionTable
    /// The loops around the code being lowered, innermost last.
    var loops: [Loop] = []

    init(builder: consuming FunctionBuilder, functions: FunctionTable) {
        self.builder = builder
        self.functions = functions
    }

    /// Makes the IR body of the statements lowered so far, which are the body of a function whose result type is
    /// `result`.
    consuming func body(returning result: RayoType) -> IRBody {
        // End the last block, which a run reaches only in a Void function: the checker makes others return first.
        builder.end(with: result == .void ? .return(nil) : .unreachable)
        return builder.body()
    }
}
