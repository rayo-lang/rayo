internal import CLLVM

/// The C library function a program prints with, and the functions `rayoc` defines around the program: the C
/// entry point, and the one that reports a panic.
struct Runtime {
    let module: ModuleBuilder
    let printf: FunctionValue
    let panic: FunctionValue
    /// The `printf` format that prints an Int on a line of its own.
    let intFormat: LLVMValueRef

    init(in module: ModuleBuilder, panicExitCode: Int32) {
        self.module = module
        printf = module.addFunction("printf", returning: module.int32, parameters: [module.pointer], isVariadic: true)
        panic = Self.definePanic(in: module, exitCode: panicExitCode)
        intFormat = module.addConstant("rayo.int_format", bytes: Array("%lld\n\0".utf8))
    }

    /// Defines the C entry point, which runs `main` and exits with 0.
    func defineEntryPoint(calling main: FunctionValue) {
        let entryPoint = module.addFunction("main", returning: module.int32)
        LLVMPositionBuilderAtEnd(module.builder, module.appendBlock(to: entryPoint.value, named: "entry"))
        module.call(main, [])
        LLVMBuildRet(module.builder, LLVMConstInt(module.int32, 0, 0))
    }

    /// Defines the function that reports a panic, given its message and the message's length, and exits with
    /// `exitCode`. It writes what the program printed before it reports the panic, so the report comes last.
    private static func definePanic(in module: ModuleBuilder, exitCode: Int32) -> FunctionValue {
        let fflush = module.addFunction("fflush", returning: module.int32, parameters: [module.pointer])
        let write = module.addFunction("write", returning: module.int64,
                                       parameters: [module.int32, module.pointer, module.int64])
        let exit = module.addFunction("exit", returning: module.void, parameters: [module.int32])
        let panic = module.addFunction("rayo.panic", returning: module.void, parameters: [module.pointer, module.int64],
                                       linkage: LLVMPrivateLinkage)
        addNoReturn(to: exit.value, in: module)
        addNoReturn(to: panic.value, in: module)

        LLVMPositionBuilderAtEnd(module.builder, module.appendBlock(to: panic.value, named: "entry"))
        module.call(fflush, [LLVMConstNull(module.pointer)])
        module.call(write, [LLVMConstInt(module.int32, 2, 0), LLVMGetParam(panic.value, 0), LLVMGetParam(panic.value, 1)])
        module.call(exit, [LLVMConstInt(module.int32, UInt64(exitCode), 0)])
        LLVMBuildUnreachable(module.builder)
        return panic
    }

    private static func addNoReturn(to function: LLVMValueRef, in module: ModuleBuilder) {
        let kind = LLVMGetEnumAttributeKindForName("noreturn", "noreturn".utf8.count)
        LLVMAddAttributeAtIndex(function, LLVMAttributeIndex(truncatingIfNeeded: LLVMAttributeFunctionIndex),
                                LLVMCreateEnumAttribute(module.context, kind, 0))
    }
}
