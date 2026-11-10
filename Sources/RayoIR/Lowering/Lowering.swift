import RayoSema

/// Lowers a checked program to Rayo IR, one function at a time.
public enum Lowering {
    public static func lower(_ program: CheckedProgram) -> IRProgram {
        IRProgram(functions: program.functions.map(lower), main: program.main)
    }

    static func lower(_ function: CheckedFunction) -> IRFunction {
        // Lower the body into a graph whose first locals are the function's own.
        let builder = FunctionBuilder(locals: function.locals.map(IRLocal.init))
        var statements = StatementLowering(builder: builder)
        statements.lower(function.body)

        // End the last block, which a run reaches only in a Void function: the checker makes others return first.
        builder.end(with: function.result == .void ? .return(nil) : .unreachable)
        return builder.function(lowering: function)
    }
}

private extension IRLocal {
    init(_ local: CheckedLocal) {
        self = .source(name: local.name, kind: local.kind, type: local.type)
    }
}
