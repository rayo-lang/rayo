import RayoSema

/// Checks that IR keeps its types, which code generation takes as given.
public enum IRVerifier {
    /// The first declaration or operation in `program` that breaks the IR's types, or nil where none does: each
    /// primary initializer's declaration in the order of its ID, then each body in the order of its function's ID and
    /// of its blocks.
    public static func verify(_ program: IRProgram) -> IRViolation? {
        for id in program.functions.ids {
            if let violation = violation(of: program.functions[id], in: program.types) { return violation }
        }

        for (id, body) in program.definedFunctions {
            let verifier = FunctionVerifier(body: body, of: program.functions[id], in: program)
            // The first violation found ends the check.
            do { try verifier.verify() } catch { return error }
        }
        return nil
    }

    /// The violation of `declaration`, where it is a primary initializer whose parameters aren't the types of its
    /// struct's fields, in order, among `types`. A call of one is built from its arguments as the struct's fields.
    private static func violation(of declaration: FunctionDeclaration, in types: TypeTable) -> IRViolation? {
        guard case .primaryInitializer(let id) = declaration.kind else { return nil }
        let fields = types[id].fields.map(\.type)
        guard declaration.parameters != fields else { return nil }

        let takes = "takes (\(list(declaration.parameters))), where its fields are (\(list(fields)))"
        return IRViolation(function: declaration.name, message: "the IR's primary initializer of '\(id.name)' \(takes)")
    }

    private static func list(_ types: [RayoType]) -> String {
        types.map(\.description).joined(separator: ", ")
    }
}
