import RayoCheckedProgram

/// Checks the rules of IR that the stages after the one that gave it take as given.
public enum IRVerifier {
    /// The first declaration or operation in `program`, which `stage` gave, that breaks the IR's rules, or nil where
    /// none does. Declarations are checked before bodies, each in the order of its function's ID.
    public static func verify(_ program: IRProgram, from stage: IRStage) -> IRViolation? {
        firstViolation(in: program) { body, declaration throws(IRViolation) in
            try verifySharedRules(in: body, of: declaration, in: program)
            try verifyStageRules(of: stage, in: body, of: declaration)
        }
    }

    /// The first declaration or operation in `program`, which the ownership stage gave, that breaks a rule the emitter
    /// takes as given, or nil where none does. Those are all its rules but where its accesses end.
    package static func verifyEmitterRules(_ program: IRProgram) -> IRViolation? {
        firstViolation(in: program) { body, declaration throws(IRViolation) in
            try verifySharedRules(in: body, of: declaration, in: program)
            try verifyOwnershipRulesOfTheEmitter(in: body, of: declaration)
        }
    }

    /// Throws the first violation in `body`, the body of `declaration`, of the rules of the ownership stage's IR that
    /// the emitter takes as given: of where its accesses begin, then of where its locals retire.
    private static func verifyOwnershipRulesOfTheEmitter(
        in body: IRBody, of declaration: FunctionDeclaration,
    ) throws(IRViolation) {
        try BegunAccessVerifier(body: body, of: declaration.name).verify()
        try LocalLifeVerifier(body: body, of: declaration.name).verify()
    }

    /// The first violation in `program`: of a function's declaration, in the order of its ID, or else the first that
    /// `verifyBody` throws for a function's body and declaration, in the order of its ID.
    private static func firstViolation(
        in program: IRProgram,
        verifyingEachBodyBy verifyBody: (IRBody, FunctionDeclaration) throws(IRViolation) -> Void,
    ) -> IRViolation? {
        for id in program.functions.ids {
            if let violation = nameViolation(of: program.functions[id]) { return violation }
            if let violation = initializerViolation(of: id, in: program) { return violation }
        }

        for (id, body) in program.definedFunctions {
            // The first violation found ends the check.
            do { try verifyBody(body, program.functions[id]) } catch { return error }
        }
        return nil
    }

    /// Throws the first violation in `body`, the body of `declaration` in `program`, of the rules every stage's IR
    /// keeps: of its types, then of the places it changes, then of the blocks its paths reach, then of its indices.
    private static func verifySharedRules(
        in body: IRBody, of declaration: FunctionDeclaration, in program: IRProgram,
    ) throws(IRViolation) {
        // The index check takes each place's type as given, so the types are checked first.
        try FunctionVerifier(body: body, of: declaration, in: program).verify()
        try ReadOnlyPlaceVerifier(body: body, of: declaration.name).verify()
        try UnreachableBlockVerifier(body: body, of: declaration.name).verify()
        try ElementIndexVerifier(body: body, of: declaration.name, types: program.types).verify()
    }

    /// Throws the first violation in `body`, the body of `declaration`, of the rules of `stage`'s IR alone: for
    /// lowering's IR, of an end or a retirement it holds, or, for the ownership stage's IR, of where its accesses end
    /// and begin and its locals retire.
    private static func verifyStageRules(
        of stage: IRStage, in body: IRBody, of declaration: FunctionDeclaration,
    ) throws(IRViolation) {
        switch stage {
        case .lowering:
            try OwnershipStatementVerifier(body: body, of: declaration.name).verify()
        // A local's life lasts through each access to it, so the accesses are checked first.
        case .ownership:
            try AccessScopeVerifier(body: body, of: declaration.name).verify()
            try verifyOwnershipRulesOfTheEmitter(in: body, of: declaration)
        }
    }

    /// The violation of `declaration` where its name doesn't spell its parameters as lowering does, as `f(_: &Int)`.
    private static func nameViolation(of declaration: FunctionDeclaration) -> IRViolation? {
        let base = String(declaration.name.prefix { $0 != "(" })
        let spelled = FunctionDeclaration.name(base, parameters: declaration.parameters)

        guard declaration.name != spelled else { return nil }
        let message = "the IR names the function '\(declaration.name)', where its parameters name it '\(spelled)'"
        return IRViolation(function: declaration.name, message: message)
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
