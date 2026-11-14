import RayoSema

/// Lowers a checked program to Rayo IR, one function body at a time. A function the checked program holds no body
/// for, since its body is tainted, has none in the IR either.
public enum Lowering {
    public static func lower(_ program: CheckedProgram) -> IRProgram {
        // Lower each body, which ends as the result type of its function says.
        var bodies: [FunctionID: IRBody] = [:]
        for (id, body) in program.bodies {
            bodies[id] = lower(body, returning: program.functions[id].result)
        }

        return IRProgram(types: program.types, functions: program.functions, bodies: bodies, main: program.main,
                         mainMayHaveFailed: program.mainMayHaveFailed)
    }

    /// Lowers `body`, the body of a function whose result type is `result`.
    static func lower(_ body: CheckedBody, returning result: RayoType) -> IRBody {
        let builder = FunctionBuilder(locals: body.locals.map(IRLocal.init))
        var lowering = FunctionLowering(builder: builder)
        lowering.lower(body.statements)
        return lowering.body(returning: result)
    }
}

private extension IRLocal {
    init(_ local: CheckedLocal) {
        self = .source(name: local.name, kind: local.kind, type: local.type)
    }
}
