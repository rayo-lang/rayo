/// Chains `steps` into one step, which runs them in the order they're written, each on what the step before it
/// gives. A step that doesn't take what the step before it gives doesn't compile.
func pipeline<Steps: CompilationStep>(@PipelineBuilder _ steps: () -> Steps) -> Steps {
    steps()
}

/// Builds one step out of the steps a `pipeline` lists.
@resultBuilder
enum PipelineBuilder {
    static func buildPartialBlock<Step: CompilationStep>(first: Step) -> Step {
        first
    }

    static func buildPartialBlock<Earlier: CompilationStep, Next: CompilationStep>(
        accumulated: Earlier, next: Next,
    ) -> Chained<Earlier, Next> {
        Chained(first: accumulated, second: next)
    }
}
