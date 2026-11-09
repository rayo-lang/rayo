internal import CLLVM

/// Why LLVM can't compile for the host, or nil when it can. Initialising it registers the host's target, once per
/// process, since registration isn't safe to run on two threads at once.
private let nativeTargetError: String? = {
    if LLVMInitializeNativeTarget() != 0 { return "LLVM can't target this host" }
    if LLVMInitializeNativeAsmPrinter() != 0 { return "LLVM can't write object code for this host" }
    return nil
}()

/// LLVM's code generator for the host, which compiles a module to object code, optimised or not.
final class TargetMachine {
    let machine: LLVMTargetMachineRef
    let triple: String
    let optimizes: Bool

    init(optimizes: Bool) throws(LLVMError) {
        if let nativeTargetError { throw LLVMError(message: nativeTargetError) }
        let triple = takeMessage(LLVMGetDefaultTargetTriple())
        var target: LLVMTargetRef?
        var error: UnsafeMutablePointer<CChar>?
        guard LLVMGetTargetFromTriple(triple, &target, &error) == 0, let target else {
            throw LLVMError(message: "LLVM can't target '\(triple)': \(takeMessage(error))")
        }
        // A generic CPU, like a C compiler's default, lets an executable built here run on any machine with the
        // same triple. Position-independent code links into the position-independent executables that clang
        // makes by default on Linux.
        machine = LLVMCreateTargetMachine(target, triple, "", "",
                                          optimizes ? LLVMCodeGenLevelDefault : LLVMCodeGenLevelNone,
                                          LLVMRelocPIC, LLVMCodeModelDefault)
        self.triple = triple
        self.optimizes = optimizes
    }

    deinit {
        LLVMDisposeTargetMachine(machine)
    }

    /// Sets `module`'s triple and data layout to the host's, which optimisation and code generation read.
    func configure(_ module: LLVMModuleRef) {
        LLVMSetTarget(module, triple)
        let layout = LLVMCreateTargetDataLayout(machine)
        LLVMSetModuleDataLayout(module, layout)
        LLVMDisposeTargetData(layout)
    }

    /// Optimises `module` if this optimises, and returns its object code.
    func objectCode(of module: ModuleBuilder) throws(LLVMError) -> [UInt8] {
        if optimizes { try optimize(module) }
        var buffer: LLVMMemoryBufferRef?
        var error: UnsafeMutablePointer<CChar>?
        guard LLVMTargetMachineEmitToMemoryBuffer(machine, module.module, LLVMObjectFile, &error, &buffer) == 0,
              let buffer else {
            throw module.error("LLVM couldn't write object code:", detail: takeMessage(error))
        }
        defer { LLVMDisposeMemoryBuffer(buffer) }
        let bytes = UnsafeRawBufferPointer(start: LLVMGetBufferStart(buffer), count: LLVMGetBufferSize(buffer))
        return Array(bytes)
    }

    /// Runs the optimisations a C compiler runs at -O2.
    private func optimize(_ module: ModuleBuilder) throws(LLVMError) {
        let options = LLVMCreatePassBuilderOptions()
        defer { LLVMDisposePassBuilderOptions(options) }
        guard let error = LLVMRunPasses(module.module, "default<O2>", machine, options) else { return }
        let message = LLVMGetErrorMessage(error)
        defer { LLVMDisposeErrorMessage(message) }
        throw module.error("LLVM couldn't optimise the module:", detail: message.map { String(cString: $0) } ?? "")
    }
}
