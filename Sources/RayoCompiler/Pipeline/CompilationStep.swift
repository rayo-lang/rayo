import RayoDiagnostics

/// One stage of a compile, which turns what the stage before it gives into what the stage after it needs, and adds
/// the errors it finds in the program to the compile's errors.
protocol CompilationStep<Input, Output> {
    associatedtype Input
    associatedtype Output

    /// Gives what the step makes of `input`, or nil when the errors it adds to `errors` leave it nothing to make. It
    /// throws only when `rayoc` itself can't go on.
    func run(_ input: Input, errors: inout [Diagnostic]) throws(CompilationError) -> Output?

    /// Takes the place of `run` when a step before this one gave nothing, so this one has no input. A step that ends
    /// the compile on the program's errors ends it here, with `errors`; any other does nothing.
    func skip(errors: [Diagnostic]) throws(CompilationError)
}

extension CompilationStep {
    func skip(errors: [Diagnostic]) {}
}
