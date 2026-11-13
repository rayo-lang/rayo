/// Checks that IR keeps its types, which code generation takes as given.
public enum IRVerifier {
    /// The first operation in `program`, in the order of its functions' IDs and of each body's blocks, that breaks
    /// the IR's types, or nil where none does.
    public static func verify(_ program: IRProgram) -> IRViolation? {
        for (id, body) in program.definedFunctions {
            let verifier = FunctionVerifier(body: body, of: program.functions[id], in: program)
            // The first violation found ends the check.
            do { try verifier.verify() } catch { return error }
        }
        return nil
    }
}
