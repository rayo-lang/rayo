@testable import RayoLLVM
import RayoSema

/// A module for the host, and the emitter of a program into it, made as a debug or a release build makes them.
struct ProgramModule {
    let target: TargetMachine
    let module: ModuleBuilder
    let emitter: ProgramEmitter

    /// A module for a program whose structs `types` holds, none by default.
    init(for build: Build, types: TypeTable = TypeTable(structs: [])) throws(LLVMError) {
        target = try TargetMachine(optimizes: build == .release)
        module = ModuleBuilder(named: "main.rayo", for: target)
        emitter = ProgramEmitter(
            module: module,
            runtime: try Runtime(in: module),
            types: types,
            sourcePath: "main.rayo",
            checksOverflow: build == .debug,
        )
    }
}

/// Runs `body` on a new module made as `build` makes it, for a program whose structs `types` holds, and keeps the
/// module, which owns every LLVM type and value read from it, alive until `body` returns.
func withProgramModule(
    for build: Build, types: TypeTable = TypeTable(structs: []), _ body: (ProgramModule) throws -> Void,
) throws {
    let programModule = try ProgramModule(for: build, types: types)
    try withExtendedLifetime(programModule) { try body(programModule) }
}
