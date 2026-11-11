/// One stage of a compile, which turns what the stage before it gives into what the stage after it needs, or stops
/// the compile.
protocol CompilationStep<Input, Output> {
    associatedtype Input
    associatedtype Output

    func run(_ input: Input) throws(CompilationError) -> Output
}
