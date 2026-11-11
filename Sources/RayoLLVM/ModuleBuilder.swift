internal import CLLVM
import LLVM

/// An LLVM module for the host, in a context of its own, and the IR builder that adds to it.
final class ModuleBuilder {
    private let llvmContext: Context
    private let llvmModule: Module
    private let llvmBuilder: Builder
    /// The modules parsed from LLVM IR, linked together, until they are linked into this module.
    private var parsed: Module?

    let void: LLVMTypeRef
    let bool: LLVMTypeRef
    let int8: LLVMTypeRef
    let int32: LLVMTypeRef
    let int64: LLVMTypeRef

    init(named name: String, for target: TargetMachine) {
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

        target.configure(llvmModule.ref)
    }

    var context: LLVMContextRef { llvmContext.ref }
    var module: LLVMModuleRef { llvmModule.ref }
    var builder: LLVMBuilderRef { llvmBuilder.ref }

    /// Throws what LLVM finds wrong with the module, which is a fault in the code that built it.
    func verify() throws(LLVMError) {
        try llvmModule.verify()
    }

    /// Throws the errors LLVM has reported in this module's context, if any.
    func checkReportedErrors() throws(LLVMError) {
        // Only an error fails the module; a warning fails nothing.
        if !llvmContext.reportedErrors.isEmpty { throw error("LLVM reported errors:") }
    }

    /// An error that says `summary`, then `detail` and the errors LLVM has reported in this module's context,
    /// whichever there are.
    func error(_ summary: String, detail: String = "") -> LLVMError {
        let reasons = ([detail] + llvmContext.reportedErrors).filter { !$0.isEmpty }
        return LLVMError(message: ([summary] + reasons).joined(separator: "\n"))
    }

    /// Parses `llvmIR`, for the same target as this module, to link into it later with the other text parsed.
    func parse(_ llvmIR: [UInt8], named name: String) throws(LLVMError) {
        // The parsed module builds for this module's target, so the two link.
        let module = try llvmContext.parseModule(llvmIR, named: name)
        module.target = llvmModule.target
        module.dataLayout = llvmModule.dataLayout

        // The first text parsed takes in the rest.
        if let earlier = parsed.take() {
            try earlier.link(module)
            parsed = Optional(earlier)
        } else {
            parsed = Optional(module)
        }
    }

    /// Declares the function `name` that the text parsed defines, with the type it is defined with.
    func declare(_ name: String) throws(LLVMError) -> FunctionValue {
        // A function the text doesn't define is a fault in the runtime rayoc carries.
        guard let definition = parsed?.function(named: name) else {
            throw LLVMError(message: "the runtime defines no function '\(name)'")
        }
        return functionValue(llvmModule.addFunction(named: name, type: definition.type))
    }

    /// Links the text parsed into this module.
    func linkParsed() throws(LLVMError) {
        // Without text parsed, nothing is linked.
        guard let parsed = parsed.take() else { return }
        try llvmModule.link(parsed)
    }

    /// Gives every function and global the module defines, but the functions `exported` names and LLVM's own
    /// globals, a linkage that keeps it out of the executable's symbols.
    func hideDefinitions(except exported: Set<String>) {
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
        constant.hasUnnamedAddress = true
        return constant.ref
    }

    /// Adds a constant `value` named `name`, for code linked into the module to read.
    func addConstant(_ name: String, int32 value: Int32) {
        addConstant(name, llvmContext.integerType(I32.self).constant(Int64(value)))
    }

    @discardableResult
    private func addConstant(_ name: String, _ initializer: some ValueHandle) -> GlobalVariable {
        let constant = llvmModule.addGlobal(named: name, initializer: initializer)
        constant.isConstant = true
        return constant
    }

    func appendBlock(to function: LLVMValueRef, named name: String) -> LLVMBasicBlockRef {
        llvmContext.appendBlock(named: name, to: Function(function)).ref
    }

    /// Emits a call of `function` with `arguments`, and returns its result, or nil where it returns nothing.
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
