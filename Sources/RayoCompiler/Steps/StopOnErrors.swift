import RayoDiagnostics

/// Ends the compile when the program has errors, and otherwise gives its input on as it is. It is the one step that
/// ends a compile for the program's errors. A warning ends it only where warnings are errors.
struct StopOnErrors<Value>: CompilationStep {
    /// Whether a warning ends the compile, as an error does.
    var warningsAreErrors: Bool

    func run(_ input: Value, errors: inout [Diagnostic]) throws(CompilationError) -> Value? {
        guard !errors.contains(where: endsCompile) else { throw .rejected(errors.inSourceOrder) }
        return input
    }

    /// Ends the compile with every error in `errors`, in source order. A step before this one gives nothing only when
    /// the program has errors, so the compile ends whenever this step is skipped.
    func skip(errors: [Diagnostic]) throws(CompilationError) {
        throw .rejected(errors.inSourceOrder)
    }

    /// Whether `diagnostic` ends the compile.
    private func endsCompile(_ diagnostic: Diagnostic) -> Bool {
        diagnostic.severity == .error || warningsAreErrors
    }
}
