import CLLVM
import RayoIR
@testable import RayoLLVM
import RayoSema
import Testing

@Suite("The LLVM types a program is emitted with")
struct EmittedTypeTests {
    @Test(arguments: [(RayoType.int, "i64"), (RayoType.bool, "i1")])
    func `a function's signature holds its parameters and result in their types`(
        result: RayoType, resultText: String,
    ) throws {
        let pick = try pick(returning: result, [])
        try withEmitted(IRProgram(functions: [voidMain, pick], main: FunctionID(index: 0))) { module in
            let signature = try signature(of: pick.name, in: module)
            #expect(try parameterTypes(of: signature) == ["i64", "i1"])
            #expect(text(of: LLVMGetReturnType(signature)) == resultText)
        }
    }

    @Test func `a function that returns nothing is declared returning void`() throws {
        try withEmitted(IRProgram(functions: [voidMain], main: FunctionID(index: 0))) { module in
            let signature = try signature(of: "rayo.main", in: module)
            #expect(try parameterTypes(of: signature) == [])
            #expect(text(of: LLVMGetReturnType(signature)) == "void")
        }
    }

    @Test func `each local's slot, a parameter's too, holds the type of its value`() throws {
        let pick = try pick(returning: .int, [.temporary(.bool), .temporary(.int)])
        try withEmitted(IRProgram(functions: [voidMain, pick], main: FunctionID(index: 0))) { module in
            let emittedPick = try function(named: pick.name, in: module)
            #expect(slotTypes(of: emittedPick) == ["i64", "i1", "i1", "i64"])
        }
    }

    /// A `main` that takes nothing, returns nothing and does nothing.
    private var voidMain: IRFunction {
        mainFunction(locals: [], [BasicBlock(statements: [], terminator: .return(nil))])
    }

    /// A function that takes an Int and a Bool, holds `temporaries` besides them, and returns the parameter of type
    /// `result`.
    private func pick(returning result: RayoType, _ temporaries: [IRLocal]) throws -> IRFunction {
        let parameters: [IRLocal] = [
            .source(name: "n", kind: .parameter, type: .int), .source(name: "b", kind: .parameter, type: .bool),
        ]
        let returned = try #require(parameters.firstIndex { $0.type == result })
        return IRFunction(
            name: "pick(_: Int, _: Bool)", parameterCount: 2, result: result, locals: parameters + temporaries,
            blocks: [BasicBlock(statements: [], terminator: .return(read(returned)))],
        )
    }

    /// Emits `program` into a new module for the host, as a debug build does, and runs `checks` on the module.
    private func withEmitted(_ program: IRProgram, _ checks: (ModuleBuilder) throws -> Void) throws {
        try withProgramModule(for: .debug) { programModule in
            programModule.emitter.emit(program)
            try checks(programModule.module)
        }
    }

    /// The function named `name` in `module`.
    private func function(named name: String, in module: ModuleBuilder) throws -> LLVMValueRef {
        try #require(LLVMGetNamedFunction(module.module, name))
    }

    /// The type of the function named `name` in `module`: its parameters and its result.
    private func signature(of name: String, in module: ModuleBuilder) throws -> LLVMTypeRef {
        try #require(LLVMGlobalGetValueType(try function(named: name, in: module)))
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
