internal import CLLVM

/// An LLVM context and the errors LLVM reports in it, which disposes of the context once nothing holds it.
final class OwnedContext {
    let ref: LLVMContextRef
    private(set) var errors: [String] = []

    init() {
        ref = LLVMContextCreate()

        // Without a handler, LLVM prints what it reports to standard error, and exits on an error.
        LLVMContextSetDiagnosticHandler(ref, { info, context in
            Unmanaged<OwnedContext>.fromOpaque(context!).takeUnretainedValue().record(info!)
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        LLVMContextDispose(ref)
    }

    /// Keeps what LLVM reports where it is an error.
    private func record(_ info: LLVMDiagnosticInfoRef) {
        let message = takeMessage(LLVMGetDiagInfoDescription(info))
        // A warning or a remark fails nothing, so only an error is kept.
        if LLVMGetDiagInfoSeverity(info) == LLVMDSError { errors.append(message) }
    }
}
