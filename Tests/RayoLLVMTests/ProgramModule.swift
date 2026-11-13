import LLVM
import RayoIR
@testable import RayoLLVM
import Testing

/// A program's emitter for the host, with the runtime's functions declared in its module, made as a debug or a
/// release build makes them.
struct ProgramModule: ~Copyable {
    let target: TargetMachine
    let emitter: ProgramEmitter
    /// The functions of the runtime that the program calls. The runtime itself is never linked in.
    let runtime: RuntimeFunctions

    init(for build: Build) throws(LLVMError) {
        // Make the build's machine, the program's emitter for it, and the runtime's functions in the emitter's
        // module. Each can throw, so all come before any field is set: Swift can't track a field that isn't
        // copyable set on one path only.
        let target = try TargetMachine(optimizes: build.optimizes)
        let emitter = ProgramEmitter(sourcePath: "main.rayo", for: target, build: build)
        let runtime = try Runtime(for: emitter)

        // Keep the runtime's functions, which outlive the runtime's own module.
        self.runtime = runtime.functions
        self.emitter = emitter
        self.target = target
    }

    /// Ends the program module, handing on the LLVM module it emits into.
    consuming func takeModule() -> Module {
        emitter.takeModule()
    }

    /// Emits `executable` into the module, as the build does.
    func emit(_ executable: IRExecutable) throws(LLVMError) {
        try emitter.emit(executable, calling: runtime)
    }
}

/// Runs `body` on a new module made as `build` makes it, and keeps the module, which owns every LLVM type and value
/// read from it, alive until `body` returns.
func withProgramModule(for build: Build, _ body: (borrowing ProgramModule) throws -> Void) throws {
    let programModule = try ProgramModule(for: build)
    try withExtendedLifetime(programModule) { try body(programModule) }
}

/// Emits `executable` into a new module for the host, as a debug build does, and runs `checks` on the module.
func withEmitted(_ executable: IRExecutable, _ checks: (borrowing Module) throws -> Void) throws {
    try withProgramModule(for: .debug) { programModule in
        try programModule.emit(executable)
        try checks(programModule.emitter.module)
    }
}

/// The function named `name` in `module`.
func function(named name: String, in module: borrowing Module) throws -> Function {
    let found = module.function(named: name)
    return try #require(found)
}

/// The instructions of `function` that `opcode` names, in the order its blocks hold them.
func instructions(_ opcode: Opcode, in function: Function) -> [Instruction] {
    function.blocks.flatMap(\.instructions).filter { $0.opcode == opcode }
}
