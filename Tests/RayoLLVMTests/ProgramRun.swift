import LLVM
@testable import RayoLLVM

/// Emits the program that `text` writes as Rayo IR, as `build` does, and runs it in this process: what it printed, and
/// the panic that ended it, if one did. A panic names the file `main.rayo`.
func run(_ text: String, in build: Build = .debug) throws -> InProcessJIT.Run {
    try jit(text, in: build).runMain()
}

/// Emits the program that `text` writes as Rayo IR, as `build` does, and runs it in this process, on a thread of its
/// own: what it printed and the panic that ended it, as `run(_:in:)` gives them, and the bytes of the thread's stack
/// the run used.
func runMeasuringStack(_ text: String, in build: Build) throws -> (run: InProcessJIT.Run, stackBytes: Int) {
    try jit(text, in: build).runMainMeasuringStack()
}

/// Emits the program that `text` writes as Rayo IR, as `build` does, and readies it to run in this process.
private func jit(_ text: String, in build: Build) throws -> InProcessJIT {
    // Emit the program, and ready its module as the build does, exporting the entry function the run calls.
    let program = try ProgramModule(for: build)
    program.emit(try executable(text))
    try LLVMEmitter.ready(program.emitter.module, for: program.target, exporting: [RuntimeFunction.main.symbol])

    return try InProcessJIT(running: program.takeModule())
}
