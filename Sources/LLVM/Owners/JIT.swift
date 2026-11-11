internal import CLLVM

/// LLVM's JIT for the host, which compiles the functions of the modules it is given when they are first looked up,
/// to run in this process.
public struct JIT: ~Copyable {
    private let ref: LLVMOrcLLJITRef

    public init() throws(LLVMError) {
        // A host whose target LLVM couldn't register has no JIT.
        if let nativeTargetError { throw LLVMError(message: nativeTargetError) }

        // Make a JIT for the host, or throw LLVM's reason it made none.
        var made: LLVMOrcLLJITRef?
        try check(LLVMOrcCreateLLJIT(&made, nil), "LLVM couldn't make a JIT")
        // LLVM reports why it made no JIT, so a missing one with no report is LLVM's own failure.
        guard let made else { throw LLVMError(message: "LLVM made no JIT, and reported no error") }
        ref = made
    }

    deinit {
        // No caller can act on an error that disposing of the JIT reports, so it is dropped.
        LLVMConsumeError(LLVMOrcDisposeLLJIT(ref))
    }

    /// Hands `module` to the JIT, which compiles its functions when they are first looked up.
    public func add(_ module: consuming Module) throws(LLVMError) {
        // The JIT owns the context of each module it takes, and `module`'s context is shared with what else was
        // made in it, so the JIT takes a copy of `module`, read from its bitcode into a context of its own.
        let bitcode = LLVMWriteBitcodeToMemoryBuffer(module.ref)!
        defer { LLVMDisposeMemoryBuffer(bitcode) }
        let context = LLVMContextCreate()!
        var copy: LLVMModuleRef?
        // Bitcode LLVM just wrote that it can't read back is LLVM's own failure.
        guard LLVMParseBitcodeInContext2(context, bitcode, &copy) == 0, let copy else {
            LLVMContextDispose(context)
            throw LLVMError(message: "LLVM couldn't read back the bitcode of \(module.name)")
        }

        // The copy goes to the JIT in a context the two share, which the JIT takes whether or not it can add it.
        let threadSafeContext = LLVMOrcCreateNewThreadSafeContextFromLLVMContext(context)
        let threadSafeModule = LLVMOrcCreateNewThreadSafeModule(copy, threadSafeContext)
        LLVMOrcDisposeThreadSafeContext(threadSafeContext)
        let added = LLVMOrcLLJITAddLLVMIRModule(ref, LLVMOrcLLJITGetMainJITDylib(ref), threadSafeModule)
        try check(added, "LLVM's JIT couldn't take \(module.name)")
    }

    /// Defines the function `name` as the code at `address`, which calls of it in the modules the JIT is given
    /// reach.
    public func define(_ name: String, at address: UnsafeRawPointer) throws(LLVMError) {
        // Make a definition of `name`, exported and callable, at `address`.
        let exported = LLVMJITSymbolGenericFlagsExported.rawValue | LLVMJITSymbolGenericFlagsCallable.rawValue
        let flags = LLVMJITSymbolFlags(GenericFlags: UInt8(exported), TargetFlags: 0)
        let symbol = LLVMJITEvaluatedSymbol(Address: LLVMOrcExecutorAddress(UInt(bitPattern: address)), Flags: flags)
        var pair = LLVMOrcCSymbolMapPair(Name: LLVMOrcLLJITMangleAndIntern(ref, name), Sym: symbol)
        let definition = LLVMOrcAbsoluteSymbols(&pair, 1)

        // A definition the JIT refuses stays the caller's to dispose of.
        let error = LLVMOrcJITDylibDefine(LLVMOrcLLJITGetMainJITDylib(ref), definition)
        if error != nil { LLVMOrcDisposeMaterializationUnit(definition) }
        try check(error, "LLVM's JIT couldn't define '\(name)'")
    }

    /// The address of the code of the function `name`, which the JIT compiles where it hasn't yet.
    public func address(of name: String) throws(LLVMError) -> UnsafeRawPointer {
        var address: LLVMOrcExecutorAddress = 0
        try check(LLVMOrcLLJITLookup(ref, &address, name), "LLVM couldn't look up '\(name)' in the JIT")
        // A lookup that succeeds gives the code's address, which is never null.
        return UnsafeRawPointer(bitPattern: UInt(address))!
    }
}

/// Throws the error `error` reports, after `summary`, where there is one.
private func check(_ error: LLVMErrorRef?, _ summary: String) throws(LLVMError) {
    // No error is a success.
    guard let error else { return }
    throw LLVMError(message: "\(summary):\n\(takeMessage(error))")
}
