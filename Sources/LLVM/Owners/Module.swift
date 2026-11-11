package import CLLVM

/// An LLVM module: the functions and globals that compile to one object file.
public struct Module: ~Copyable {
    package let ref: LLVMModuleRef
    private let context: OwnedContext
    /// Whether this disposes of the module, which it doesn't once another module has taken it in a link.
    private var owns = true

    init(_ ref: LLVMModuleRef, in context: OwnedContext) {
        self.ref = ref
        self.context = context
    }

    deinit {
        // A module that another took in a link was disposed of by the link.
        if owns { LLVMDisposeModule(ref) }
    }

    public var name: String {
        var length = 0
        let name = LLVMGetModuleIdentifier(ref, &length)!
        return String(decoding: UnsafeRawBufferPointer(start: name, count: length), as: UTF8.self)
    }

    /// The triple of the target the module compiles for.
    public var target: String {
        get { String(cString: LLVMGetTarget(ref)) }
        nonmutating set { LLVMSetTarget(ref, newValue) }
    }

    /// How the target lays out values in memory, as LLVM IR writes it.
    public var dataLayout: String {
        get { String(cString: LLVMGetDataLayoutStr(ref)) }
        nonmutating set { LLVMSetDataLayout(ref, newValue) }
    }

    /// The module as LLVM IR writes it.
    public var text: String { takeMessage(LLVMPrintModuleToString(ref)) }

    /// Throws what LLVM finds wrong with the module, which is a fault in the code that built it.
    public func verify() throws(LLVMError) {
        var message: UnsafeMutablePointer<CChar>?
        let broken = LLVMVerifyModule(ref, LLVMReturnStatusAction, &message) != 0
        let report = takeMessage(message)
        // A broken module's report says what LLVM found wrong with it.
        if broken { throw LLVMError(message: "LLVM rejected the module it was given:\n\(report)") }
    }

    /// Links `other` into this module, which takes its functions and globals in.
    public func link(_ other: consuming Module) throws(LLVMError) {
        // Link `other` in, which LLVM disposes of whether or not the link succeeds.
        let otherName = other.name
        let earlierErrors = reportedErrorCount
        let failed = LLVMLinkModules2(ref, other.ref) != 0
        other.owns = false

        // A link that succeeds is done; one that fails throws the errors LLVM reported as it linked.
        guard failed else { return }
        throw error("LLVM couldn't link \(otherName) into \(name):", reportedAfter: earlierErrors)
    }

    /// How many errors LLVM has reported in the module's context.
    package var reportedErrorCount: Int { context.errors.count }

    /// An error that says `summary`, then `detail` and the errors LLVM reported in the module's context after the
    /// first `earlier` of them, whichever there are.
    package func error(_ summary: String, detail: String = "", reportedAfter earlier: Int) -> LLVMError {
        let reasons = ([detail] + context.errors.dropFirst(earlier)).filter { !$0.isEmpty }
        return LLVMError(message: ([summary] + reasons).joined(separator: "\n"))
    }

    // MARK: Functions and globals

    /// Declares a function named `name` of `type`, which a block appended to it defines.
    public func addFunction(named name: String, type: FunctionType) -> Function {
        Function(LLVMAddFunction(ref, name, type.ref), type: type)
    }

    /// The function named `name` that the module declares or defines.
    public func function(named name: String) -> Function? {
        LLVMGetNamedFunction(ref, name).map(Function.init)
    }

    /// The functions the module declares or defines, in order.
    public var functions: [Function] {
        var functions: [Function] = []
        var next = LLVMGetFirstFunction(ref)
        while let function = next {
            functions.append(Function(function))
            next = LLVMGetNextFunction(function)
        }
        return functions
    }

    /// The global variables the module declares or defines, in order.
    public var globals: [GlobalVariable] {
        var globals: [GlobalVariable] = []
        var next = LLVMGetFirstGlobal(ref)
        while let global = next {
            globals.append(GlobalVariable(global))
            next = LLVMGetNextGlobal(global)
        }
        return globals
    }

    /// Adds a global variable named `name`, which holds `initializer` when a run starts.
    public func addGlobal(named name: String, initializer: some ValueHandle) -> GlobalVariable {
        let global = LLVMAddGlobal(ref, LLVMTypeOf(initializer.anyValue.ref), name)!
        LLVMSetInitializer(global, initializer.anyValue.ref)
        return GlobalVariable(global)
    }

    /// The declaration of LLVM's intrinsic `name` that takes and returns values of `type`.
    public func intrinsic(named name: String, overloadedOn type: some TypeHandle) -> Function {
        let id = LLVMLookupIntrinsicID(name, name.utf8.count)
        var types: [LLVMTypeRef?] = [type.anyType.ref]
        return Function(LLVMGetIntrinsicDeclaration(ref, id, &types, 1))
    }
}
