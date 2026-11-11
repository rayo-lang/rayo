internal import CLLVM

/// An LLVM context, and what LLVM reports in it, kept alive by the context and by each module and builder made in
/// it, so that none of them outlives it.
final class ContextHandle {
    let ref: LLVMContextRef
    /// The errors LLVM has reported in the context, in order.
    private(set) var errors: [String] = []

    init() {
        ref = LLVMContextCreate()

        // Without a handler, LLVM prints what it reports to standard error, and exits on an error.
        LLVMContextSetDiagnosticHandler(ref, { info, handle in
            Unmanaged<ContextHandle>.fromOpaque(handle!).takeUnretainedValue().record(info!)
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        LLVMContextDispose(ref)
    }

    /// Keeps what LLVM reports, if it is an error; a warning or a remark fails nothing.
    private func record(_ info: LLVMDiagnosticInfoRef) {
        let message = takeMessage(LLVMGetDiagInfoDescription(info))
        if LLVMGetDiagInfoSeverity(info) == LLVMDSError { errors.append(message) }
    }
}
