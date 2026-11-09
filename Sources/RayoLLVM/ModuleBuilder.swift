internal import CLLVM

/// An LLVM module for the host, in a context of its own, and the IR builder that adds to it.
final class ModuleBuilder {
    let context: LLVMContextRef
    let module: LLVMModuleRef
    let builder: LLVMBuilderRef

    let void: LLVMTypeRef
    let bool: LLVMTypeRef
    let int32: LLVMTypeRef
    let int64: LLVMTypeRef
    let pointer: LLVMTypeRef

    init(named name: String, for target: TargetMachine) {
        context = LLVMContextCreate()
        module = LLVMModuleCreateWithNameInContext(name, context)
        builder = LLVMCreateBuilderInContext(context)
        void = LLVMVoidTypeInContext(context)
        bool = LLVMInt1TypeInContext(context)
        int32 = LLVMInt32TypeInContext(context)
        int64 = LLVMInt64TypeInContext(context)
        pointer = LLVMPointerTypeInContext(context, 0)
        target.configure(module)
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

    func addFunction(_ name: String, returning result: LLVMTypeRef, parameters: [LLVMTypeRef] = [],
                     isVariadic: Bool = false, linkage: LLVMLinkage = LLVMExternalLinkage) -> FunctionValue {
        var parameters = parameters.map { Optional($0) }
        let type = LLVMFunctionType(result, &parameters, UInt32(parameters.count), isVariadic ? 1 : 0)!
        let function = LLVMAddFunction(module, name, type)!
        LLVMSetLinkage(function, linkage)
        return FunctionValue(value: function, type: type)
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
