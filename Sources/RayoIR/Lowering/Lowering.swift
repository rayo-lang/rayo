import RayoSema

/// Lowers a checked program to Rayo IR, one function at a time.
public enum Lowering {
    public static func lower(_ program: CheckedProgram) -> IRProgram {
        IRProgram(types: program.types, functions: program.functions.map(lower), main: program.main)
    }

    static func lower(_ function: CheckedFunction) -> IRFunction {
        // Lower the body's statements into the function's blocks.
        var builder = FunctionBuilder(locals: function.locals.map(IRLocal.init))
        StatementLowering.lower(function.body, in: &builder)

        // End the last block, which a run reaches only in a Void function: the checker makes others return first.
        builder.end(with: function.result == .void ? .return(nil) : .unreachable)
        return builder.function(of: function)
    }
}

private extension IRLocal {
    init(_ local: CheckedLocal) {
        self = .source(name: local.name, kind: local.kind, type: local.type)
    }
}
