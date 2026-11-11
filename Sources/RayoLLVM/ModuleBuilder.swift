internal import CLLVM
import LLVM

/// An LLVM module for the host, in a context of its own, and the IR builder that adds to it.
final class ModuleBuilder {
    private let llvmContext: Context
    let llvmModule: Module
    private let llvmBuilder: Builder

    let void: LLVMTypeRef
    let bool: LLVMTypeRef
    let int8: LLVMTypeRef
    let int32: LLVMTypeRef
    let int64: LLVMTypeRef

    init(named name: String, for target: borrowing TargetMachine) {
        // Make the module, its builder and the types it builds with, in a context of their own.
        let context = Context()
        llvmModule = context.makeModule(named: name)
        llvmBuilder = context.makeBuilder()
        void = context.voidType.ref
        bool = context.integerType(I1.self).ref
        int8 = context.integerType(I8.self).ref
        int32 = context.integerType(I32.self).ref
        int64 = context.integerType(I64.self).ref
        llvmContext = context

        target.configure(llvmModule)
    }

    var context: LLVMContextRef { llvmContext.ref }
    var module: LLVMModuleRef { llvmModule.ref }
    var builder: LLVMBuilderRef { llvmBuilder.ref }

    /// Throws the errors LLVM has reported in this module's context, if any.
    func checkReportedErrors() throws(LLVMError) {
        // Only an error fails the module; a warning fails nothing.
        if !llvmContext.reportedErrors.isEmpty { throw llvmModule.error("LLVM reported errors:", reportedAfter: 0) }
    }

    /// Makes an empty module in this module's context, for the same target, so that the two link.
    func makeModule(named name: String) -> Module {
        targeted(llvmContext.makeModule(named: name))
    }

    /// Parses `llvmIR` into a module of this module's context, for the same target, so that the two link.
    func parse(_ llvmIR: [UInt8], named name: String) throws(LLVMError) -> Module {
        targeted(try llvmContext.parseModule(llvmIR, named: name))
    }

    /// `module`, set to build for this module's target.
    private func targeted(_ module: consuming Module) -> Module {
        module.target = llvmModule.target
        module.dataLayout = llvmModule.dataLayout
        return module
    }

    /// Links `other`, a module of this module's context, into this one.
    func link(_ other: consuming Module) throws(LLVMError) {
        try llvmModule.link(other)
    }

    /// Declares the function that another module defines as `definition`, by its name and type.
    func declare(_ definition: Function) -> FunctionValue {
        functionValue(llvmModule.addFunction(named: definition.name, type: definition.type))
    }

    /// Readies the module to compile as `target`'s build: hides every definition but the functions `exported` names
    /// from code outside the module, checks the module is well formed, and optimises it if `target` optimises.
    func ready(for target: borrowing TargetMachine, exporting exported: Set<String>) throws(LLVMError) {
        hideDefinitions(except: exported)
        try llvmModule.verify()
        if target.optimizes { try target.optimize(llvmModule) }
    }

    /// Gives every function and global the module defines, but the functions `exported` names and LLVM's own
    /// globals, a linkage that keeps it out of the executable's symbols.
    private func hideDefinitions(except exported: Set<String>) {
        // Functions become internal, so that optimisation can drop those nothing calls.
        for function in llvmModule.functions where isHideable(function) && !exported.contains(function.name) {
            function.setLinkage(.internal)
        }

        // Globals become private, so that optimisation can drop those nothing reads.
        for global in llvmModule.globals where isHideable(global) {
            global.setLinkage(.private)
        }
    }

    /// Whether `value` is a definition, and not one of LLVM's own, such as `llvm.used` or `llvm.global_ctors`,
    /// whose linkage LLVM requires to stay as it is.
    private func isHideable(_ value: some GlobalValue) -> Bool {
        !value.isDeclaration && !value.name.hasPrefix("llvm.")
    }

    func addFunction(_ name: String, taking parameters: [LLVMTypeRef],
                     returning result: LLVMTypeRef) -> FunctionValue {
        let type = llvmContext.functionType(returning: AnyType(result), taking: parameters.map(AnyType.init))
        return functionValue(llvmModule.addFunction(named: name, type: type))
    }

    /// The declaration of the LLVM intrinsic `name`, for the overload on `type`.
    func intrinsic(_ name: String, overloadedOn type: LLVMTypeRef) -> FunctionValue {
        functionValue(llvmModule.intrinsic(named: name, overloadedOn: AnyType(type)))
    }

    /// Adds a constant array holding `bytes`, and returns it.
    func addConstant(_ name: String, bytes: [UInt8]) -> LLVMValueRef {
        let constant = addConstant(name, llvmContext.constant(bytes: bytes))
        constant.setUnnamedAddress()
        return constant.ref
    }

    /// Adds a constant `value` named `name`, for code linked into the module to read.
    func addConstant(_ name: String, int32 value: Int32) {
        addConstant(name, llvmContext.integerType(I32.self).constant(Int64(value)))
    }

    @discardableResult
    private func addConstant(_ name: String, _ initializer: some ValueHandle) -> GlobalVariable {
        let constant = llvmModule.addGlobal(named: name, initializer: initializer)
        constant.setConstant()
        return constant
    }

    func appendBlock(to function: LLVMValueRef, named name: String) -> LLVMBasicBlockRef {
        llvmContext.appendBlock(named: name, to: Function(function)).ref
    }

    @discardableResult
    func call(_ function: FunctionValue, _ arguments: [LLVMValueRef]) -> LLVMValueRef? {
        let callee = Function(function.value, type: FunctionType(function.type))
        return llvmBuilder.call(callee, arguments.map(AnyValue.init))?.ref
    }

    func constant(_ value: Int64) -> LLVMValueRef {
        llvmContext.integerType(I64.self).constant(value).ref
    }

    func constant(_ value: Bool) -> LLVMValueRef {
        llvmContext.integerType(I1.self).constant(value ? 1 : 0).ref
    }

    /// `function` as the emitters call it: its value and its type.
    private func functionValue(_ function: Function) -> FunctionValue {
        FunctionValue(value: function.ref, type: function.type.ref)
    }
}
