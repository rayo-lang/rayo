@testable import RayoLLVM

/// A module for the host, and the emitter of a program into it, made as a debug or a release build makes them.
struct ProgramModule {
    let target: TargetMachine
    let module: ModuleBuilder
    let emitter: ProgramEmitter

    init(for build: Build) throws(LLVMError) {
        target = try TargetMachine(optimizes: build == .release)
        module = ModuleBuilder(named: "main.rayo", for: target)
        emitter = ProgramEmitter(
            module: module,
            runtime: try Runtime(in: module),
            sourcePath: "main.rayo",
            checksOverflow: build == .debug,
        )
    }
}
