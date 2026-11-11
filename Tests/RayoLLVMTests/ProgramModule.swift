import LLVM
@testable import RayoLLVM

/// A module for the host, and the emitter of a program into it, made as a debug or a release build makes them.
struct ProgramModule: ~Copyable {
    let target: TargetMachine
    let module: ModuleBuilder
    let emitter: ProgramEmitter

    init(for build: Build) throws(LLVMError) {
        // Make the build's machine, a module for it, and the runtime the program's code calls. Each can throw, so
        // all come before any field is set: Swift can't track a field that isn't copyable set on one path only.
        let target = try TargetMachine(optimizes: build == .release)
        let module = ModuleBuilder(named: "main.rayo", for: target)
        let runtime = try Runtime(in: module)

        // Emit into the module as the build does, with the runtime's functions to call.
        emitter = ProgramEmitter(module: module, runtime: runtime.functions, sourcePath: "main.rayo",
                                 checksOverflow: build == .debug)
        self.module = module
        self.target = target
    }
}

/// Runs `body` on a new module made as `build` makes it, and keeps the module, which owns every LLVM type and value
/// read from it, alive until `body` returns.
func withProgramModule(for build: Build, _ body: (borrowing ProgramModule) throws -> Void) throws {
    let programModule = try ProgramModule(for: build)
    try withExtendedLifetime(programModule) { try body(programModule) }
}
