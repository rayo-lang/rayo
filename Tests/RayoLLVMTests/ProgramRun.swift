import LLVM
@testable import RayoLLVM

/// Emits the program that `text` writes as Rayo IR, as `build` does, and runs it in this process: what it printed, and
/// the panic that ended it, if one did. A panic names the file `main.rayo`.
func run(_ text: String, in build: Build = .debug) throws -> InProcessJIT.Run {
    // Emit the program, and ready its module as the build does, exporting the entry function the run calls.
    let program = try ProgramModule(for: build)
    program.emit(try executable(text))
    try LLVMEmitter.ready(program.emitter.module, for: program.target, exporting: [RuntimeFunction.main.symbol])

    return try InProcessJIT(running: program.takeModule()).runMain()
}
