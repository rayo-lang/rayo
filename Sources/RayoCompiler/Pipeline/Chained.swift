import RayoDiagnostics

/// Two steps run one after the other, the second on what the first gives, and both adding to one list of errors.
struct Chained<First: CompilationStep, Second: CompilationStep>: CompilationStep where First.Output == Second.Input {
    var first: First
    var second: Second

    func run(_ input: First.Input, errors: inout [Diagnostic]) throws(CompilationError) -> Second.Output? {
        // A first step that gives nothing leaves the second without its input, so the second is skipped.
        guard let output = try first.run(input, errors: &errors) else {
            try second.skip(errors: errors)
            return nil
        }
        return try second.run(output, errors: &errors)
    }

    func skip(errors: [Diagnostic]) throws(CompilationError) {
        try first.skip(errors: errors)
        try second.skip(errors: errors)
    }
}
