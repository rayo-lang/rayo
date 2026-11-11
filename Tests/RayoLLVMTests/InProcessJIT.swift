import CLLVM
import CLLVMJIT
import LLVM
@testable import RayoLLVM
import RayoLLVMTestSupport

/// LLVM IR loaded into this process, whose functions LLVM compiles when they are first looked up and which run
/// here, with a call to the runtime's `rayo.panic` ending the call that reached it instead of the process.
struct InProcessJIT: ~Copyable {
    /// What a call came to: the value it returned, or the message of the panic that ended it.
    enum Call {
        case returned(Int64)
        case panicked(String)
    }

    private let jit: LLVMOrcLLJITRef

    /// Loads `llvmIR`, a module that leaves `rayo.panic` undefined. LLVM's native target must be initialized
    /// already, as making a `TargetMachine` does.
    init(llvmIR: String) throws(LLVMError) {
        // Make a JIT for the host.
        var made: LLVMOrcLLJITRef?
        try Self.check(LLVMOrcCreateLLJIT(&made, nil))
        // LLVM reports why it made no JIT, so a missing one with no report is LLVM's own failure.
        guard let jit = made else { throw LLVMError(message: "LLVM made no JIT, and reported no error") }

        // A JIT that can't take the module is disposed of here, since no instance owns it yet.
        do {
            try Self.catchPanics(in: jit)
            try Self.add(llvmIR, to: jit)
        } catch {
            Self.dispose(jit)
            throw error
        }

        self.jit = jit
    }

    deinit {
        Self.dispose(jit)
    }

    /// Runs the function `name`, of type `(i64, i64) -> i64`, on `left` and `right`.
    func call(_ name: String, _ left: Int64, _ right: Int64) throws(LLVMError) -> Call {
        // Compile the function, and call it where a panic ends the call.
        var address: LLVMOrcExecutorAddress = 0
        try Self.check(LLVMOrcLLJITLookup(jit, &address, name))
        let function = unsafeBitCast(UnsafeRawPointer(bitPattern: UInt(address))!,
                                     to: (@convention(c) (Int64, Int64) -> Int64).self)
        let outcome = rayo_call_catching_panic(function, left, right)

        // A call that returned comes to its value.
        guard outcome.panicked else { return .returned(outcome.value) }

        // A panic's message lives in the JIT's memory, so it is copied out while the JIT still holds it.
        let message = UnsafeRawBufferPointer(start: outcome.message, count: Int(outcome.length))
        return .panicked(String(decoding: message, as: UTF8.self))
    }

    /// Defines `rayo.panic` in `jit` as the stand-in that ends a call with its message.
    private static func catchPanics(in jit: LLVMOrcLLJITRef) throws(LLVMError) {
        // Make a definition of `rayo.panic` at the stand-in's address.
        let exported = LLVMJITSymbolGenericFlagsExported.rawValue | LLVMJITSymbolGenericFlagsCallable.rawValue
        let flags = LLVMJITSymbolFlags(GenericFlags: UInt8(exported), TargetFlags: 0)
        var panic = LLVMOrcCSymbolMapPair(Name: LLVMOrcLLJITMangleAndIntern(jit, "rayo.panic"),
                                          Sym: LLVMJITEvaluatedSymbol(Address: rayo_test_panic_address(), Flags: flags))
        let definition = LLVMOrcAbsoluteSymbols(&panic, 1)

        // A definition the JIT refuses stays the caller's to dispose of.
        let error = LLVMOrcJITDylibDefine(LLVMOrcLLJITGetMainJITDylib(jit), definition)
        if error != nil { LLVMOrcDisposeMaterializationUnit(definition) }
        try check(error)
    }

    /// Parses `llvmIR` and hands the module to `jit`, which then owns it.
    private static func add(_ llvmIR: String, to jit: LLVMOrcLLJITRef) throws(LLVMError) {
        // Copy the text into a buffer LLVM reads, in a context of the module's own.
        let context = LLVMContextCreate()
        let buffer = LLVMCreateMemoryBufferWithMemoryRangeCopy(llvmIR, llvmIR.utf8.count, "module")
        defer { LLVMDisposeMemoryBuffer(buffer) }

        // Text LLVM can't parse fails with LLVM's report of it, and takes its context with it.
        var module: LLVMModuleRef?
        var message: UnsafeMutablePointer<CChar>?
        guard LLVMParseIRInContext2(context, buffer, &module, &message) == 0, let module else {
            let report = takeMessage(message)
            LLVMContextDispose(context)
            throw LLVMError(message: "LLVM couldn't parse the module:\n\(report)")
        }

        // The module goes to the JIT in a context the two share.
        let threadSafeContext = LLVMOrcCreateNewThreadSafeContextFromLLVMContext(context)
        let threadSafeModule = LLVMOrcCreateNewThreadSafeModule(module, threadSafeContext)
        LLVMOrcDisposeThreadSafeContext(threadSafeContext)
        try check(LLVMOrcLLJITAddLLVMIRModule(jit, LLVMOrcLLJITGetMainJITDylib(jit), threadSafeModule))
    }

    /// Disposes of `jit`, and of any error that disposing of it reports.
    private static func dispose(_ jit: LLVMOrcLLJITRef) {
        // No caller can act on an error disposing reports, so it is dropped here.
        LLVMConsumeError(LLVMOrcDisposeLLJIT(jit))
    }

    /// Throws the error that `error` reports, if any.
    private static func check(_ error: LLVMErrorRef?) throws(LLVMError) {
        // No error is a success.
        guard let error else { return }

        // An error throws with LLVM's message for it, which LLVM then frees.
        let message = LLVMGetErrorMessage(error)
        defer { LLVMDisposeErrorMessage(message) }
        throw LLVMError(message: String(cString: message!))
    }
}
