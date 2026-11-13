import LLVM
import RayoIR
@testable import RayoLLVM
import Testing

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
