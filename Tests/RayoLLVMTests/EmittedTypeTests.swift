import CLLVM
import LLVM
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
        let irFunction = try pick(returning: result, [])

        // The emitted signature takes an i64 and an i1, and returns the LLVM type of `result`.
        try withEmitted(program(of: [emptyMain, irFunction])) { module in
            let signature = try signature(of: irFunction.name, in: module)
            #expect(try parameterTypes(of: signature) == ["i64", "i1"])
            #expect(text(of: LLVMGetReturnType(signature)) == resultText)
        }
    }

    @Test func `a struct is passed and returned by value, as its named LLVM type`() throws {
        let parameter = IRLocal.source(name: "p", kind: .parameter, type: pairType)
        let relay = IRFunction(
            name: "relay(_: Pair)", parameterCount: 1, result: pairType, locals: [parameter],
            blocks: [BasicBlock(statements: [], terminator: .return(read(0)))],
        )

        // The emitted signature takes a Pair and returns one, neither through a pointer. LLVM writes a named struct
        // type with its body.
        let pairText = "%Pair = type <{ i64, i1, [7 x i8] }>"
        try withEmitted(program(of: [emptyMain, relay], types: pairTable)) { module in
            let signature = try signature(of: relay.name, in: module)
            #expect(try parameterTypes(of: signature) == [pairText])
            #expect(text(of: LLVMGetReturnType(signature)) == pairText)
        }
    }

    @Test func `a function that returns nothing is declared returning void`() throws {
        try withEmitted(program(of: [emptyMain])) { module in
            let signature = try signature(of: "rayo.main", in: module)
            #expect(try parameterTypes(of: signature) == [])
            #expect(text(of: LLVMGetReturnType(signature)) == "void")
        }
    }

    @Test func `each local's slot, a parameter's too, holds the type of its value`() throws {
        let irFunction = try pick(returning: .int, [.temporary(.bool), .temporary(.int)])

        // The emitted function allocates a slot of each local's LLVM type, its parameters' first.
        try withEmitted(program(of: [emptyMain, irFunction])) { module in
            let llvmFunction = try function(named: irFunction.name, in: module)
            let slotTypes = instructions(LLVMAlloca, in: llvmFunction).map { text(of: LLVMGetAllocatedType($0)) }
            #expect(slotTypes == ["i64", "i1", "i1", "i64"])
        }
    }

    @Test func `each local's slot is aligned as its type is, a struct's as its most-aligned field`() throws {
        let main = mainFunction(locals: [.bool, pairType, .int], [BasicBlock(statements: [], terminator: .return(nil))])

        // The emitted `main` aligns the Bool's slot to 1, and the Pair's and the Int's to 8.
        try withEmitted(program(of: [main], types: pairTable)) { module in
            let slots = instructions(LLVMAlloca, in: try function(named: "rayo.main", in: module))
            #expect(slots.map(LLVMGetAlignment) == [1, 8, 8])
        }
    }

    @Test func `a load and a store of a struct are aligned as the struct is`() throws {
        // `main` copies one Pair into another, so it loads the first and stores the second.
        let main = mainFunction(locals: [pairType, pairType], [
            BasicBlock(statements: [statement(storingIn: 1, .use(read(0)))], terminator: .return(nil)),
        ])

        // The emitted copy reads and writes 8-byte-aligned memory.
        try withEmitted(program(of: [main], types: pairTable)) { module in
            let llvmMain = try function(named: "rayo.main", in: module)
            #expect(instructions(LLVMLoad, in: llvmMain).map(LLVMGetAlignment) == [8])
            #expect(instructions(LLVMStore, in: llvmMain).map(LLVMGetAlignment) == [8])
        }
    }

    /// A struct of a Bool and an Int, which lies as the Int, then the Bool, then 7 bytes of padding.
    private let pairTable = TypeTable(structs: [
        StructType(name: "Pair", fields: [Field(name: "flag", type: .bool), Field(name: "count", type: .int)]),
    ])

    /// The type of the struct `pairTable` holds.
    private let pairType = RayoType.structure(StructID(index: 0, name: "Pair"))

    /// A `main` that takes nothing, returns nothing and does nothing.
    private var emptyMain: IRFunction {
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

    /// Emits `executable` into a new module for the host, as a debug build does, and runs `checks` on the module.
    private func withEmitted(_ executable: IRExecutable, _ checks: (borrowing Module) throws -> Void) throws {
        try withProgramModule(for: .debug) { programModule in
            programModule.emit(executable)
            try checks(programModule.emitter.module)
        }
    }

    /// The function named `name` in `module`.
    private func function(named name: String, in module: borrowing Module) throws -> LLVMValueRef {
        try #require(LLVMGetNamedFunction(module.ref, name))
    }

    /// The type of the function named `name` in `module`: its parameters and its result.
    private func signature(of name: String, in module: borrowing Module) throws -> LLVMTypeRef {
        try #require(LLVMGlobalGetValueType(try function(named: name, in: module)))
    }

    /// The types of the parameters `signature` takes, as LLVM writes them.
    private func parameterTypes(of signature: LLVMTypeRef) throws -> [String] {
        var parameters = [LLVMTypeRef?](repeating: nil, count: Int(LLVMCountParamTypes(signature)))
        LLVMGetParamTypes(signature, &parameters)
        return try parameters.map { text(of: try #require($0)) }
    }

    /// The instructions of `function` that `opcode` names, in the order its blocks hold them.
    private func instructions(_ opcode: LLVMOpcode, in function: LLVMValueRef) -> [LLVMValueRef] {
        var found: [LLVMValueRef] = []
        var block = LLVMGetFirstBasicBlock(function)
        while let currentBlock = block {
            // Walk the block's instructions in order.
            var instruction = LLVMGetFirstInstruction(currentBlock)
            while let current = instruction {
                // An instruction of the opcode is one the caller checks, such as a slot's load or store; any other
                // is passed over.
                if LLVMGetInstructionOpcode(current) == opcode { found.append(current) }
                instruction = LLVMGetNextInstruction(current)
            }
            block = LLVMGetNextBasicBlock(currentBlock)
        }
        return found
    }
}
