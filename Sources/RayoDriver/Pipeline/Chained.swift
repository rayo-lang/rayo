/// Two steps run one after the other, the second on what the first gives.
struct Chained<First: CompilationStep, Second: CompilationStep>: CompilationStep where First.Output == Second.Input {
    var first: First
    var second: Second

    func run(_ input: First.Input) throws(CompilationError) -> Second.Output {
        try second.run(try first.run(input))
    }
}
