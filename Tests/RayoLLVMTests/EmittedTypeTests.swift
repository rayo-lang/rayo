import CLLVM
import RayoIR
@testable import RayoLLVM
import RayoSema
import Testing

@Suite("The LLVM types a program is emitted with")
struct EmittedTypeTests {
    @Test func `a function's signature holds its parameters and result in their types`() throws {
        let pick = IRFunction(
            name: "pick(_: Int, _: Bool)", parameterCount: 2, result: .bool,
            locals: [
                .source(name: "n", kind: .parameter, type: .int), .source(name: "b", kind: .parameter, type: .bool),
            ],
            blocks: [BasicBlock(statements: [], terminator: .return(read(1)))],
        )
        let emitted = try emit(IRProgram(functions: [voidMain, pick], main: FunctionID(index: 0)))

        // The module owns the function and its types, so it lives until the checks have read them.
        try withExtendedLifetime(emitted) {
            let signature = try signature(of: "pick(_: Int, _: Bool)", in: emitted)
            #expect(try parameterTypes(of: signature) == ["i64", "i1"])
            #expect(text(of: LLVMGetReturnType(signature)) == "i1")
        }
    }

    @Test func `a function that returns nothing is declared returning void`() throws {
        let emitted = try emit(IRProgram(functions: [voidMain], main: FunctionID(index: 0)))

        // The module owns the function and its types, so it lives until the checks have read them.
        try withExtendedLifetime(emitted) {
            let signature = try signature(of: "rayo.main", in: emitted)
            #expect(try parameterTypes(of: signature) == [])
            #expect(text(of: LLVMGetReturnType(signature)) == "void")
        }
    }

    @Test func `each local's slot holds the type of its value`() throws {
        let program = function(locals: [.int, .bool, .int], [BasicBlock(statements: [], terminator: .return(nil))])
        let emitted = try emit(program)

        // The module owns the function and its slots, so it lives until the check has read them.
        try withExtendedLifetime(emitted) {
            let main = try #require(LLVMGetNamedFunction(emitted.module, "rayo.main"))
            #expect(slotTypes(of: main) == ["i64", "i1", "i64"])
        }
    }

    /// A `main` that takes nothing, returns nothing and does nothing.
    private var voidMain: IRFunction {
        mainFunction(locals: [], [BasicBlock(statements: [], terminator: .return(nil))])
    }

    /// Emits `program` into a new module for the host, as a debug build does, and returns the module.
    private func emit(_ program: IRProgram) throws(LLVMError) -> ModuleBuilder {
        let emitting = try ProgramModule(for: .debug)
        emitting.emitter.emit(program)
        return emitting.module
    }

    /// The type of the function `module` names `name`: its parameters and its result.
    private func signature(of name: String, in module: ModuleBuilder) throws -> LLVMTypeRef {
        let function = try #require(LLVMGetNamedFunction(module.module, name))
        return try #require(LLVMGlobalGetValueType(function))
    }

    /// The types of the parameters `signature` takes, as LLVM writes them.
    private func parameterTypes(of signature: LLVMTypeRef) throws -> [String] {
        var parameters = [LLVMTypeRef?](repeating: nil, count: Int(LLVMCountParamTypes(signature)))
        LLVMGetParamTypes(signature, &parameters)
        return try parameters.map { text(of: try #require($0)) }
    }

    /// The types of the stack slots that `function`'s entry block allocates, in order, as LLVM writes them.
    private func slotTypes(of function: LLVMValueRef) -> [String] {
        var types: [String] = []
        var instruction = LLVMGetFirstInstruction(LLVMGetEntryBasicBlock(function))
        while let current = instruction {
            // Only an alloca makes a slot; the entry block also stores the arguments and branches to the first block.
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
