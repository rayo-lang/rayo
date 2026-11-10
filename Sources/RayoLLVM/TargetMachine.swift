internal import CLLVM

/// Why LLVM can't compile for the host, or nil when it can. Initialising it registers the host's target, once per
/// process, since registration isn't safe to run on two threads at once.
private let nativeTargetError: String? = {
    // Without the host's target, LLVM can't compile for it at all.
    if LLVMInitializeNativeTarget() != 0 { return "LLVM can't target this host" }
    // Without its assembly printer, LLVM can compile for the host but not write the object code.
    if LLVMInitializeNativeAsmPrinter() != 0 { return "LLVM can't write object code for this host" }
    return nil
}()

/// LLVM's code generator for the host, which compiles a module to object code, optimised or not.
final class TargetMachine {
    let machine: LLVMTargetMachineRef
    let triple: String
    let optimizes: Bool

    /// A code generator for the host that optimises when `optimizes` is true. Throws when LLVM can't target the
    /// host.
    init(optimizes: Bool) throws(LLVMError) {
        // A host LLVM can't target has no code generator.
        if let nativeTargetError { throw LLVMError(message: nativeTargetError) }

        // Find LLVM's target for the host's triple.
        let triple = takeMessage(LLVMGetDefaultTargetTriple())
        var target: LLVMTargetRef?
        var error: UnsafeMutablePointer<CChar>?
        // A triple that LLVM was built without a target for can't be compiled for.
        guard LLVMGetTargetFromTriple(triple, &target, &error) == 0, let target else {
            throw LLVMError(message: "LLVM can't target '\(triple)': \(takeMessage(error))")
        }

        // Make the code generator for the triple, at the optimisation level asked for.
        machine = LLVMCreateTargetMachine(
            target, triple,
            // Code for a generic CPU without extra features, a C compiler's default, runs on any machine of the triple.
            "", "",
            optimizes ? LLVMCodeGenLevelDefault : LLVMCodeGenLevelNone,
            // Position-independent code links into the position-independent executables clang makes by default on
            // Linux.
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

    /// Optimises `module` if this optimises, and returns its object code. Throws when LLVM can't optimise the
    /// module or write its object code.
    func objectCode(of module: ModuleBuilder) throws(LLVMError) -> [UInt8] {
        // A machine that optimises optimises the module before it compiles it.
        if optimizes { try optimize(module) }

        // Compile the module into a buffer of object code.
        var buffer: LLVMMemoryBufferRef?
        var error: UnsafeMutablePointer<CChar>?
        // A module LLVM can't compile reports why.
        guard LLVMTargetMachineEmitToMemoryBuffer(machine, module.module, LLVMObjectFile, &error, &buffer) == 0,
              let buffer else {
            throw module.error("LLVM couldn't write object code:", detail: takeMessage(error))
        }
        defer { LLVMDisposeMemoryBuffer(buffer) }

        // Copy the object code out of the buffer, which is freed once this returns.
        let bytes = UnsafeRawBufferPointer(start: LLVMGetBufferStart(buffer), count: LLVMGetBufferSize(buffer))
        return Array(bytes)
    }

    /// Runs on `module` the optimisations a C compiler runs at -O2. Throws when LLVM can't run them.
    private func optimize(_ module: ModuleBuilder) throws(LLVMError) {
        // Run the passes of -O2 over the module.
        let options = LLVMCreatePassBuilderOptions()
        defer { LLVMDisposePassBuilderOptions(options) }
        // Passes that all succeed leave nothing to report.
        guard let error = LLVMRunPasses(module.module, "default<O2>", machine, options) else { return }

        // A pass that fails reports why.
        let message = LLVMGetErrorMessage(error)
        defer { LLVMDisposeErrorMessage(message) }
        throw module.error("LLVM couldn't optimise the module:", detail: message.map { String(cString: $0) } ?? "")
    }
}
