import RayoSema

/// Lowers a checked program to Rayo IR, one function at a time.
public enum Lowering {
    public static func lower(_ program: CheckedProgram) -> IRProgram {
        IRProgram(types: program.types, functions: program.functions.map(lower), main: program.main)
    }

    static func lower(_ function: CheckedFunction) -> IRFunction {
        let builder = FunctionBuilder(locals: function.locals.map(IRLocal.init))
        var lowering = FunctionLowering(builder: builder)
        lowering.lower(function.body)
        return lowering.function(of: function)
    }
}

private extension IRLocal {
    init(_ local: CheckedLocal) {
        self = .source(name: local.name, kind: local.kind, type: local.type)
    }
}
