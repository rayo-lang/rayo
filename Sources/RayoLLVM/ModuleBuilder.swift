internal import CLLVM

/// An LLVM module for the host, in a context of its own, and the IR builder that adds to it.
final class ModuleBuilder {
    let context: LLVMContextRef
    let module: LLVMModuleRef
    let builder: LLVMBuilderRef
    private let diagnostics = DiagnosticLog()

    let void: LLVMTypeRef
    let bool: LLVMTypeRef
    let int32: LLVMTypeRef
    let int64: LLVMTypeRef

    init(named name: String, for target: TargetMachine) {
        // Make the module, its builder and the types it builds with, in a context of their own.
        context = LLVMContextCreate()
        module = LLVMModuleCreateWithNameInContext(name, context)
        builder = LLVMCreateBuilderInContext(context)
        void = LLVMVoidTypeInContext(context)
        bool = LLVMInt1TypeInContext(context)
        int32 = LLVMInt32TypeInContext(context)
        int64 = LLVMInt64TypeInContext(context)

        target.configure(module)

        // Without a handler, LLVM prints what it reports to rayoc's standard error, and exits on an error.
        LLVMContextSetDiagnosticHandler(context, { info, log in
            Unmanaged<DiagnosticLog>.fromOpaque(log!).takeUnretainedValue().record(info!)
        }, Unmanaged.passUnretained(diagnostics).toOpaque())
    }

    deinit {
        LLVMDisposeBuilder(builder)
        LLVMDisposeModule(module)
        LLVMContextDispose(context)
    }

    /// Throws what LLVM finds wrong with the module, which is a fault in the code that built it.
    func verify() throws(LLVMError) {
        var message: UnsafeMutablePointer<CChar>?
        let broken = LLVMVerifyModule(module, LLVMReturnStatusAction, &message) != 0
        let report = takeMessage(message)
        // A broken module's report says what LLVM found wrong with it.
        if broken { throw LLVMError(message: "LLVM rejected the module it was given:\n\(report)") }
    }

    /// Throws the errors LLVM has reported in this module's context, if any.
    func checkReportedErrors() throws(LLVMError) {
        // Only an error fails the module; a warning fails nothing.
        if !diagnostics.errors.isEmpty { throw error("LLVM reported errors:") }
    }

    /// An error that says `summary`, then `detail` and the errors LLVM has reported in this module's context,
    /// whichever there are.
    func error(_ summary: String, detail: String = "") -> LLVMError {
        let reasons = ([detail] + diagnostics.errors).filter { !$0.isEmpty }
        return LLVMError(message: ([summary] + reasons).joined(separator: "\n"))
    }

    /// Parses `llvmIR` into a module of this context, for the same target as this one.
    func parse(_ llvmIR: [UInt8], named name: String) throws(LLVMError) -> LLVMModuleRef {
        // Copy the text into a buffer that ends in a NUL, which LLVM's lexer reads as the end of the text.
        let buffer = llvmIR.withUnsafeBufferPointer { bytes in
            bytes.withMemoryRebound(to: CChar.self) { text in
                LLVMCreateMemoryBufferWithMemoryRangeCopy(text.baseAddress, text.count, name)
            }
        }
        defer { LLVMDisposeMemoryBuffer(buffer) }

        // Parse the buffer, or throw what LLVM reports.
        var parsed: LLVMModuleRef?
        var message: UnsafeMutablePointer<CChar>?
        let failed = LLVMParseIRInContext2(context, buffer, &parsed, &message) != 0
        let report = takeMessage(message)
        // Text LLVM can't parse fails with LLVM's report of it.
        guard !failed, let parsed else { throw LLVMError(message: "LLVM couldn't parse \(name):\n\(report)") }

        // The parsed module builds for this module's target, so the two link.
        LLVMSetTarget(parsed, LLVMGetTarget(module))
        LLVMSetDataLayout(parsed, LLVMGetDataLayoutStr(module))
        return parsed
    }

    /// Links `other` into this module, which consumes it.
    func link(_ other: LLVMModuleRef) throws(LLVMError) {
        // A module that won't link fails with the errors LLVM reported about it.
        if LLVMLinkModules2(module, other) != 0 { throw error("LLVM couldn't link the runtime:") }
    }

    /// Gives every function and global the module defines, but the functions `exported` names and LLVM's own
    /// globals, a linkage that keeps it out of the executable's symbols.
    func hideDefinitions(except exported: Set<String>) {
        // Functions become internal, so that optimisation can drop those nothing calls.
        var function = LLVMGetFirstFunction(module)
        while let current = function {
            // Each function the module defines but doesn't export becomes internal.
            if isHideable(current) && !exported.contains(name(of: current)) {
                LLVMSetLinkage(current, LLVMInternalLinkage)
            }
            function = LLVMGetNextFunction(current)
        }

        // Globals become private, so that optimisation can drop those nothing reads.
        var global = LLVMGetFirstGlobal(module)
        while let current = global {
            // Each global the module defines, but LLVM's own, becomes private.
            if isHideable(current) { LLVMSetLinkage(current, LLVMPrivateLinkage) }
            global = LLVMGetNextGlobal(current)
        }
    }

    /// Whether `value` is a definition, and not one of LLVM's own, such as `llvm.used` or `llvm.global_ctors`,
    /// whose linkage LLVM requires to stay as it is.
    private func isHideable(_ value: LLVMValueRef) -> Bool {
        LLVMIsDeclaration(value) == 0 && !name(of: value).hasPrefix("llvm.")
    }

    private func name(of value: LLVMValueRef) -> String {
        var length = 0
        let name = LLVMGetValueName2(value, &length)!
        return String(decoding: UnsafeRawBufferPointer(start: name, count: length), as: UTF8.self)
    }

    /// Declares the function `name` that one of `modules` defines, with the type it is defined with.
    func declare(_ name: String, definedIn modules: [LLVMModuleRef]) throws(LLVMError) -> FunctionValue {
        // A function none of them defines is a fault in the runtime rayoc carries.
        guard let definition = modules.lazy.compactMap({ LLVMGetNamedFunction($0, name) }).first else {
            throw LLVMError(message: "the runtime defines no function '\(name)'")
        }
        let type = LLVMGlobalGetValueType(definition)!
        return FunctionValue(value: LLVMAddFunction(module, name, type), type: type)
    }

    func addFunction(_ name: String, taking parameters: [LLVMTypeRef],
                     returning result: LLVMTypeRef) -> FunctionValue {
        var parameters = parameters.map { Optional($0) }
        let type = LLVMFunctionType(result, &parameters, UInt32(parameters.count), 0)!
        return FunctionValue(value: LLVMAddFunction(module, name, type), type: type)
    }

    /// The declaration of the LLVM intrinsic `name`, for the overload on `type`.
    func intrinsic(_ name: String, overloadedOn type: LLVMTypeRef) -> FunctionValue {
        let id = LLVMLookupIntrinsicID(name, name.utf8.count)
        var types: [LLVMTypeRef?] = [type]
        return FunctionValue(value: LLVMGetIntrinsicDeclaration(module, id, &types, 1),
                             type: LLVMIntrinsicGetType(context, id, &types, 1))
    }

    /// Adds a constant array holding `bytes`, and returns it.
    func addConstant(_ name: String, bytes: [UInt8]) -> LLVMValueRef {
        let initializer: LLVMValueRef = bytes.withUnsafeBufferPointer { buffer in
            buffer.withMemoryRebound(to: CChar.self) { text in
                LLVMConstStringInContext2(context, text.baseAddress, text.count, 1)
            }
        }
        let constant = addConstant(name, initializer)
        LLVMSetUnnamedAddress(constant, LLVMGlobalUnnamedAddr)
        return constant
    }

    /// Adds a constant `value` named `name`, for code linked into the module to read.
    func addConstant(_ name: String, int32 value: Int32) {
        addConstant(name, LLVMConstInt(int32, UInt64(UInt32(bitPattern: value)), 1))
    }

    @discardableResult
    private func addConstant(_ name: String, _ initializer: LLVMValueRef) -> LLVMValueRef {
        let constant = LLVMAddGlobal(module, LLVMTypeOf(initializer), name)!
        LLVMSetInitializer(constant, initializer)
        LLVMSetGlobalConstant(constant, 1)
        return constant
    }

    func appendBlock(to function: LLVMValueRef, named name: String) -> LLVMBasicBlockRef {
        LLVMAppendBasicBlockInContext(context, function, name)
    }

    @discardableResult
    func call(_ function: FunctionValue, _ arguments: [LLVMValueRef]) -> LLVMValueRef {
        var arguments = arguments.map { Optional($0) }
        return LLVMBuildCall2(builder, function.type, function.value, &arguments, UInt32(arguments.count), "")
    }

    func constant(_ value: Int64) -> LLVMValueRef {
        LLVMConstInt(int64, UInt64(bitPattern: value), 1)
    }

    func constant(_ value: Bool) -> LLVMValueRef {
        LLVMConstInt(bool, value ? 1 : 0, 0)
    }
}

/// What LLVM reports through a context's diagnostic handler, with the severity of each report.
private final class DiagnosticLog {
    private var reports: [(severity: LLVMDiagnosticSeverity, message: String)] = []

    var errors: [String] {
        reports.filter { $0.severity == LLVMDSError }.map(\.message)
    }

    func record(_ info: LLVMDiagnosticInfoRef) {
        reports.append((LLVMGetDiagInfoSeverity(info), takeMessage(LLVMGetDiagInfoDescription(info))))
    }
}

/// The text of an LLVM message, which this disposes of.
func takeMessage(_ message: UnsafeMutablePointer<CChar>?) -> String {
    // LLVM gives no message where it has nothing to say.
    guard let message else { return "" }
    defer { LLVMDisposeMessage(message) }
    return String(cString: message)
}
