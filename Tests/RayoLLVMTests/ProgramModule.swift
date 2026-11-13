import LLVM
import RayoIR
@testable import RayoLLVM

/// A program's emitter for the host, which declares in its module the runtime's functions that its code calls, made
/// as a debug or a release build makes them. The runtime itself is never linked in.
struct ProgramModule: ~Copyable {
    let target: TargetMachine
    let emitter: ProgramEmitter

    init(for build: Build) throws(LLVMError) {
        // Make the build's machine and the program's emitter for it. Each can throw, so both come before any field is
        // set: Swift can't track a field that isn't copyable set on one path only.
        let target = try TargetMachine(optimizes: build.optimizes)
        let emitter = try ProgramEmitter(sourcePath: "main.rayo", for: target, build: build)

        self.emitter = emitter
        self.target = target
    }

    /// Ends the program module, handing on the LLVM module it emits into.
    consuming func takeModule() -> Module {
        emitter.takeModule()
    }

    /// Emits `executable` into the module, as the build does.
    func emit(_ executable: IRExecutable) throws(LLVMError) {
        try emitter.emit(executable)
    }
}

/// Runs `body` on a new module made as `build` makes it, and keeps the module, which owns every LLVM type and value
/// read from it, alive until `body` returns.
func withProgramModule(for build: Build, _ body: (borrowing ProgramModule) throws -> Void) throws {
    let programModule = try ProgramModule(for: build)
    try withExtendedLifetime(programModule) { try body(programModule) }
}
