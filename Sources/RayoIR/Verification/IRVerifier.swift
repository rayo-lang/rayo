import RayoSema

/// Checks the rules of IR that code generation takes as given. The IR keeps its types, and each index it finds an
/// element by was checked against its array's count. The IR the ownership stage gives also ends each access once on
/// every path.
public enum IRVerifier {
    /// The first declaration or operation in `program`, which `stage` gave, that breaks the IR's rules, or nil where
    /// none does. Each primary initializer's declaration is checked in the order of its ID, then each body in the
    /// order of its function's ID.
    public static func verify(_ program: IRProgram, from stage: IRStage) -> IRViolation? {
        for id in program.functions.ids {
            if let violation = initializerViolation(of: id, in: program) { return violation }
        }

        for (id, body) in program.definedFunctions {
            // The first violation found ends the check.
            do { try verify(body, of: program.functions[id], in: program, from: stage) } catch { return error }
        }
        return nil
    }

    /// Throws the first violation in `body`, the body of `declaration` in `program`, which `stage` gave: of its types,
    /// then of its indices, then, for the ownership stage's IR, of where its accesses end.
    private static func verify(
        _ body: IRBody, of declaration: FunctionDeclaration, in program: IRProgram, from stage: IRStage,
    ) throws(IRViolation) {
        // The index check takes each place's type as given, so the types are checked first.
        try FunctionVerifier(body: body, of: declaration, in: program).verify()
        try ElementIndexVerifier(body: body, of: declaration.name, types: program.types).verify()

        // Lowering writes no end, so only the ownership stage's IR ends its accesses.
        guard stage == .ownership else { return }
        try AccessScopeVerifier(body: body, of: declaration.name).verify()
    }

    /// The violation of the function `id` of `program`, where it is a primary initializer that a call can't build its
    /// struct by: one that takes anything but its struct's fields, in order, each owned and labeled by its name, or
    /// makes another type than its struct, or has a body, or that a run starts at.
    private static func initializerViolation(of id: FunctionID, in program: IRProgram) -> IRViolation? {
        let declaration = program.functions[id]
        guard case .primaryInitializer(let structID) = declaration.kind else { return nil }
        let fields = program.types[structID].fields.map { field in
            FunctionParameter(label: field.name, convention: .owned, type: field.type)
        }
        let initializer = "primary initializer of '\(structID.name)'"

        let message: String? = if declaration.parameters != fields {
            "the IR's \(initializer) takes (\(list(declaration.parameters))), where it takes (\(list(fields)))"
        } else if declaration.result != .named(.structure(structID)) {
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

    private static func list(_ parameters: [FunctionParameter]) -> String {
        parameters.map(\.description).joined(separator: ", ")
    }
}
