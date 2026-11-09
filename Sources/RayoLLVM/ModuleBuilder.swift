internal import CLLVM

/// An LLVM module for the host, in a context of its own, and the IR builder that adds to it.
final class ModuleBuilder {
    let context: LLVMContextRef
    let module: LLVMModuleRef
    let builder: LLVMBuilderRef
    private let diagnostics = DiagnosticLog()

    let void: LLVMTypeRef
    let bool: LLVMTypeRef
    let int64: LLVMTypeRef

    init(named name: String, for target: TargetMachine) {
        context = LLVMContextCreate()
        module = LLVMModuleCreateWithNameInContext(name, context)
        builder = LLVMCreateBuilderInContext(context)
        void = LLVMVoidTypeInContext(context)
        bool = LLVMInt1TypeInContext(context)
        int64 = LLVMInt64TypeInContext(context)
        target.configure(module)
        // Without a handler, LLVM prints what it reports, and exits on an error.
        LLVMContextSetDiagnosticHandler(context, { info, log in
            let message = takeMessage(LLVMGetDiagInfoDescription(info))
            Unmanaged<DiagnosticLog>.fromOpaque(log!).takeUnretainedValue().messages.append(message)
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
        if broken { throw LLVMError(message: "LLVM rejected the module it was given:\n\(report)") }
    }

    /// Parses `llvmIR` into a module of this context, for the same target as this one.
    func parse(_ llvmIR: [UInt8], named name: String) throws(LLVMError) -> LLVMModuleRef {
        var parsed: LLVMModuleRef?
        var message: UnsafeMutablePointer<CChar>?
        let failed = llvmIR.withUnsafeBufferPointer { bytes in
            bytes.withMemoryRebound(to: CChar.self) { text in
                let buffer = LLVMCreateMemoryBufferWithMemoryRange(text.baseAddress, text.count, name, 0)
                defer { LLVMDisposeMemoryBuffer(buffer) }
                return LLVMParseIRInContext2(context, buffer, &parsed, &message) != 0
            }
        }
        let report = takeMessage(message)
        guard !failed, let parsed else { throw LLVMError(message: "LLVM couldn't parse \(name):\n\(report)") }
        LLVMSetTarget(parsed, LLVMGetTarget(module))
        LLVMSetDataLayout(parsed, LLVMGetDataLayoutStr(module))
        return parsed
    }

    /// Links `other` into this module, which consumes it.
    func link(_ other: LLVMModuleRef) throws(LLVMError) {
        diagnostics.messages = []
        if LLVMLinkModules2(module, other) != 0 {
            throw LLVMError(message: "LLVM couldn't link the runtime:\n" + diagnostics.messages.joined(separator: "\n"))
        }
    }

    /// Declares the function `name` that one of `modules` defines, with the type it is defined with.
    func declare(_ name: String, definedIn modules: [LLVMModuleRef]) throws(LLVMError) -> FunctionValue {
        guard let definition = modules.lazy.compactMap({ LLVMGetNamedFunction($0, name) }).first else {
            throw LLVMError(message: "the runtime defines no function '\(name)'")
        }
        let type = LLVMGlobalGetValueType(definition)!
        return FunctionValue(value: LLVMAddFunction(module, name, type), type: type)
    }

    func addFunction(_ name: String, returning result: LLVMTypeRef) -> FunctionValue {
        let type = LLVMFunctionType(result, nil, 0, 0)!
        return FunctionValue(value: LLVMAddFunction(module, name, type), type: type)
    }

    /// The declaration of the LLVM intrinsic `name`, for the overload on `type`.
    func intrinsic(_ name: String, overloadedOn type: LLVMTypeRef) -> FunctionValue {
        let id = LLVMLookupIntrinsicID(name, name.utf8.count)
        var types: [LLVMTypeRef?] = [type]
        return FunctionValue(value: LLVMGetIntrinsicDeclaration(module, id, &types, 1),
                             type: LLVMIntrinsicGetType(context, id, &types, 1))
    }

    /// Adds a private constant array holding `bytes`, and returns it.
    func addConstant(_ name: String, bytes: [UInt8]) -> LLVMValueRef {
        let initializer = bytes.withUnsafeBufferPointer { buffer in
            buffer.withMemoryRebound(to: CChar.self) { LLVMConstStringInContext2(context, $0.baseAddress, $0.count, 1) }
        }
        let constant = LLVMAddGlobal(module, LLVMTypeOf(initializer), name)!
        LLVMSetInitializer(constant, initializer)
        LLVMSetGlobalConstant(constant, 1)
        LLVMSetLinkage(constant, LLVMPrivateLinkage)
        LLVMSetUnnamedAddress(constant, LLVMGlobalUnnamedAddr)
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

/// The messages LLVM reports through a context's diagnostic handler.
private final class DiagnosticLog {
    var messages: [String] = []
}

/// An LLVM function, with the type that a call to it names.
struct FunctionValue {
    let value: LLVMValueRef
    let type: LLVMTypeRef
}

/// The text of an LLVM message, which this disposes of.
func takeMessage(_ message: UnsafeMutablePointer<CChar>?) -> String {
    guard let message else { return "" }
    defer { LLVMDisposeMessage(message) }
    return String(cString: message)
}
