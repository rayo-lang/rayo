import RayoSema

/// Checks that IR keeps its types, which code generation takes as given.
public enum IRVerifier {
    /// The first declaration or operation in `program` that breaks the IR's types, or nil where none does: each
    /// primary initializer's declaration in the order of its ID, then each body in the order of its function's ID and
    /// of its blocks.
    public static func verify(_ program: IRProgram) -> IRViolation? {
        for id in program.functions.ids {
            if let violation = initializerViolation(of: id, in: program) { return violation }
        }

        for (id, body) in program.definedFunctions {
            let verifier = FunctionVerifier(body: body, of: program.functions[id], in: program)
            // The first violation found ends the check.
            do { try verifier.verify() } catch { return error }
        }
        return nil
    }

    /// The violation of the function `id` of `program`, where it is a primary initializer that a call can't build its
    /// struct by: one that takes other types than its struct's fields', in order, or makes another type than its
    /// struct, or has a body, or that a run starts at.
    private static func initializerViolation(of id: FunctionID, in program: IRProgram) -> IRViolation? {
        let declaration = program.functions[id]
        guard case .primaryInitializer(let structID) = declaration.kind else { return nil }
        let fields = program.types[structID].fields.map(\.type)
        let initializer = "primary initializer of '\(structID.name)'"

        let message: String? = if declaration.parameters != fields {
            "the IR's \(initializer) takes (\(list(declaration.parameters))), where its fields are (\(list(fields)))"
        } else if declaration.result != .structure(structID) {
            "the IR's \(initializer) makes \(declaration.result), where it makes \(structID.name)"
        } else if program.bodies[id] != nil {
            "the IR gives the \(initializer) a body"
        } else if program.main == id {
            "the IR starts a run at the \(initializer), which has no body"
        } else {
            nil
        }
        return message.map { IRViolation(function: declaration.name, message: $0) }
    }

    private static func list(_ types: [RayoType]) -> String {
        types.map(\.description).joined(separator: ", ")
    }
}
