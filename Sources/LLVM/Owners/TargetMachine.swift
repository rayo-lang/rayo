internal import CLLVM

/// LLVM's code generator for the host, which optimises modules and writes their object code.
public struct TargetMachine: ~Copyable {
    private let ref: LLVMTargetMachineRef
    /// The triple that names what the machine compiles for, which is the host's unless the machine was made for
    /// another.
    public let triple: String
    /// Whether the machine compiles for Windows, which its triple names as the operating system.
    public var compilesForWindows: Bool { triple.contains("-windows") }
    /// Whether the machine optimises the machine code it generates. `optimize(_:)` optimises a module's IR either way.
    public let optimizes: Bool

    public init(optimizes: Bool) throws(LLVMError) {
        try self.init(optimizes: optimizes, triple: takeMessage(LLVMGetDefaultTargetTriple()))
    }

    /// A machine that compiles for `triple`, which must name a target that the host's own registers, such as the
    /// host's processor on another operating system.
    init(optimizes: Bool, triple: String) throws(LLVMError) {
        // A host whose target LLVM couldn't register has no machine.
        if let nativeTargetError { throw LLVMError(message: nativeTargetError) }

        // Find LLVM's target for the triple, or throw LLVM's reason it has none.
        var target: LLVMTargetRef?
        var error: UnsafeMutablePointer<CChar>?
        guard LLVMGetTargetFromTriple(triple, &target, &error) == 0, let target else {
            throw LLVMError(message: "LLVM can't target '\(triple)': \(takeMessage(error))")
        }

        // A generic CPU, like a C compiler's default, lets an executable built here run on any machine with the
        // same triple. Position-independent code links into the position-independent executables that clang
        // makes by default on Linux.
        ref = LLVMCreateTargetMachine(target, triple, "", "",
                                      optimizes ? LLVMCodeGenLevelDefault : LLVMCodeGenLevelNone,
                                      LLVMRelocPIC, LLVMCodeModelDefault)
        self.triple = triple
        self.optimizes = optimizes
    }

    deinit {
        LLVMDisposeTargetMachine(ref)
    }

    /// Sets `module`'s triple and data layout to the host's, which optimisation and code generation read.
    public func configure(_ module: borrowing Module) {
        LLVMSetTarget(module.ref, triple)
        let layout = LLVMCreateTargetDataLayout(ref)
        LLVMSetModuleDataLayout(module.ref, layout)
        LLVMDisposeTargetData(layout)
    }

    /// Runs over `module` the optimisations a C compiler runs at -O2.
    public func optimize(_ module: borrowing Module) throws(LLVMError) {
        // Run clang's -O2 pipeline, which reads the host's details from this machine.
        let earlierErrors = module.reportedErrorCount
        let options = LLVMCreatePassBuilderOptions()
        defer { LLVMDisposePassBuilderOptions(options) }
        let error = LLVMRunPasses(module.ref, "default<O2>", ref, options)

        // A pipeline that ran reports no error; one that didn't throws LLVM's message for it.
        guard let error else { return }
        throw module.error("LLVM couldn't optimise \(module.name):", detail: takeMessage(error),
                           reportedAfter: earlierErrors)
    }

    /// Writes the object code of `module`, and returns it.
    public func objectCode(of module: borrowing Module) throws(LLVMError) -> [UInt8] {
        // A frame larger than the machine can make would end the process inside LLVM, so it fails here first.
        try checkFrames(of: module)

        // Have LLVM write the object code into a buffer of its own, and fail with its report where it can't.
        let earlierErrors = module.reportedErrorCount
        var buffer: LLVMMemoryBufferRef?
        var error: UnsafeMutablePointer<CChar>?
        guard LLVMTargetMachineEmitToMemoryBuffer(ref, module.ref, LLVMObjectFile, &error, &buffer) == 0,
              let buffer else {
            throw module.error("LLVM couldn't write the object code of \(module.name):", detail: takeMessage(error),
                               reportedAfter: earlierErrors)
        }

        // Copy the object code out of LLVM's buffer, which goes once it is copied.
        defer { LLVMDisposeMemoryBuffer(buffer) }
        let bytes = UnsafeRawBufferPointer(start: LLVMGetBufferStart(buffer), count: LLVMGetBufferSize(buffer))
        return Array(bytes)
    }
}
