import CLLVM
import RayoIR
@testable import RayoLLVM
import RayoSema
import Testing

@Suite("The LLVM types a program is emitted with")
struct EmittedTypeTests {
    @Test func `a function's signature holds its parameters and result in their types`() throws(LLVMError) {
        let pick = IRFunction(
            name: "pick(_: Int, _: Bool)", parameterCount: 2, result: .bool,
            locals: [
                .source(name: "n", kind: .parameter, type: .int), .source(name: "b", kind: .parameter, type: .bool),
            ],
            blocks: [BasicBlock(statements: [], terminator: .return(read(1)))],
        )
        let module = try emitted(IRProgram(functions: [voidMain, pick], main: FunctionID(index: 0)))

        let signature = LLVMGlobalGetValueType(LLVMGetNamedFunction(module.module, "pick(_: Int, _: Bool)"))!
        #expect(parameterTypes(of: signature) == ["i64", "i1"])
        #expect(text(of: LLVMGetReturnType(signature)) == "i1")
    }

    @Test func `a function that returns nothing is declared returning void`() throws(LLVMError) {
        let module = try emitted(IRProgram(functions: [voidMain], main: FunctionID(index: 0)))

        let signature = LLVMGlobalGetValueType(LLVMGetNamedFunction(module.module, "rayo.main"))!
        #expect(parameterTypes(of: signature) == [])
        #expect(text(of: LLVMGetReturnType(signature)) == "void")
    }

    @Test func `each local's slot holds the type of its value`() throws(LLVMError) {
        let program = function(locals: [.int, .bool, .int], [BasicBlock(statements: [], terminator: .return(nil))])
        let module = try emitted(program)

        let main = LLVMGetNamedFunction(module.module, "rayo.main")!
        #expect(slotTypes(of: main) == ["i64", "i1", "i64"])
    }

    /// A `main` that takes nothing, returns nothing and does nothing.
    private var voidMain: IRFunction {
        IRFunction(name: "main()", parameterCount: 0, result: .void, locals: [],
                   blocks: [BasicBlock(statements: [], terminator: .return(nil))])
    }

    /// Emits `program` into a new module for the host, as a debug build does, and returns the module.
    private func emitted(_ program: IRProgram) throws(LLVMError) -> ModuleBuilder {
        let module = ModuleBuilder(named: "main.rayo", for: try TargetMachine(optimizes: false))
        let emitter = ProgramEmitter(module: module, runtime: try Runtime(in: module), sourcePath: "main.rayo",
                                     checksOverflow: true)
        emitter.emit(program)
        return module
    }

    /// The types of the parameters `signature` takes, as LLVM writes them.
    private func parameterTypes(of signature: LLVMTypeRef) -> [String] {
        var parameters = [LLVMTypeRef?](repeating: nil, count: Int(LLVMCountParamTypes(signature)))
        LLVMGetParamTypes(signature, &parameters)
        return parameters.map { text(of: $0!) }
    }

    /// The types of the stack slots that `function`'s entry block allocates, in order, as LLVM writes them.
    private func slotTypes(of function: LLVMValueRef) -> [String] {
        var types: [String] = []
        var instruction = LLVMGetFirstInstruction(LLVMGetEntryBasicBlock(function))
        while let current = instruction {
            // Only an alloca makes a slot; the entry block also stores arguments and branches on.
            if LLVMGetInstructionOpcode(current) == LLVMAlloca { types.append(text(of: LLVMGetAllocatedType(current))) }
            instruction = LLVMGetNextInstruction(current)
        }
        return types
    }

    /// `type` as LLVM writes it, such as `i64`.
    private func text(of type: LLVMTypeRef) -> String {
        takeMessage(LLVMPrintTypeToString(type))
    }
}
