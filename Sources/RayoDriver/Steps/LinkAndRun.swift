/// Links object code into an executable, runs it, and gives what the run gave.
struct LinkAndRun: CompilationStep {
    var toolchain: Toolchain
    var output: Driver.ProgramOutput

    func run(_ objectCode: [UInt8]) throws(CompilationError) -> Driver.Result {
        do {
            return try toolchain.linkAndRun(objectCode, output: output)
        } catch {
            throw CompilationError(error)
        }
    }
}
