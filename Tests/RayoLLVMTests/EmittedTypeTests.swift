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
            #expect(signature.parameters.map(\.text) == ["i64", "i1"])
            #expect(signature.result.text == resultText)
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
            #expect(signature.parameters.map(\.text) == [pairText])
            #expect(signature.result.text == pairText)
        }
    }

    @Test func `a function that returns nothing is declared returning void`() throws {
        try withEmitted(program(of: [emptyMain])) { module in
            let signature = try signature(of: "rayo.main", in: module)
            #expect(signature.parameters.map(\.text) == [])
            #expect(signature.result.text == "void")
        }
    }

    @Test func `each local's slot, a parameter's too, holds the type of its value`() throws {
        let irFunction = try pick(returning: .int, [.temporary(.bool), .temporary(.int)])

        // The emitted function allocates a slot of each local's LLVM type, its parameters' first.
        try withEmitted(program(of: [emptyMain, irFunction])) { module in
            let llvmFunction = try function(named: irFunction.name, in: module)
            let slotTypes = instructions(.allocate, in: llvmFunction).map(\.allocatedType?.text)
            #expect(slotTypes == ["i64", "i1", "i1", "i64"])
        }
    }

    @Test func `each local's slot is aligned as its type is, a struct's as its most-aligned field`() throws {
        let main = mainFunction(locals: [.bool, pairType, .int], [BasicBlock(statements: [], terminator: .return(nil))])

        // The emitted `main` aligns the Bool's slot to 1, and the Pair's and the Int's to 8.
        try withEmitted(program(of: [main], types: pairTable)) { module in
            let slots = instructions(.allocate, in: try function(named: "rayo.main", in: module))
            #expect(slots.map(\.alignment) == [1, 8, 8])
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
            #expect(instructions(.load, in: llvmMain).map(\.alignment) == [8])
            #expect(instructions(.store, in: llvmMain).map(\.alignment) == [8])
        }
    }

    @Test func `a struct's value holds each field's value in the element that its layout puts the field in`() throws {
        // `main` makes a Pair of its Bool and its Int, which the Pair declares in that order.
        let main = mainFunction(locals: [.bool, .int, pairType], [
            BasicBlock(
                statements: [statement(storingIn: 2, .structure(pairID, fields: [read(0), read(1)]))],
                terminator: .return(nil),
            ),
        ])

        // The Bool goes in the second element and the Int in the first.
        try withEmitted(program(of: [main], types: pairTable)) { module in
            let text = try function(named: "rayo.main", in: module).text
            #expect(text.contains("""
                  %5 = insertvalue %Pair poison, i1 %3, 1
                  %6 = insertvalue %Pair %5, i64 %4, 0
                """))
        }
    }

    @Test func `a field is read from the element that its struct's layout puts it in, aligned as its type is`() throws {
        // `main` reads the Pair's Bool, which it declares first.
        let flag = Operand.read(Place(local: LocalID(index: 0), fields: [0], range: nowhere))
        let main = mainFunction(locals: [pairType, .bool], [
            BasicBlock(statements: [statement(storingIn: 1, .use(flag))], terminator: .return(nil)),
        ])

        // The read loads one byte from the Pair's second element.
        try withEmitted(program(of: [main], types: pairTable)) { module in
            let text = try function(named: "rayo.main", in: module).text
            #expect(text.contains("""
                  %2 = getelementptr inbounds nuw %Pair, ptr %0, i32 0, i32 1
                  %3 = load i1, ptr %2, align 1
                """))
        }
    }

    /// A struct of a Bool and an Int, which lies as the Int, then the Bool, then 7 bytes of padding.
    private let pairTable = TypeTable(structs: [
        StructType(name: "Pair", fields: [Field(name: "flag", type: .bool), Field(name: "count", type: .int)]),
    ])

    /// The struct `pairTable` holds.
    private let pairID = StructID(index: 0, name: "Pair")

    /// The type of the struct `pairTable` holds.
    private var pairType: RayoType { .structure(pairID) }

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
            try programModule.emit(executable)
            try checks(programModule.emitter.module)
        }
    }

    /// The function named `name` in `module`.
    private func function(named name: String, in module: borrowing Module) throws -> Function {
        let found = module.function(named: name)
        return try #require(found)
    }

    /// The type of the function named `name` in `module`: its parameters and its result.
    private func signature(of name: String, in module: borrowing Module) throws -> FunctionType {
        try function(named: name, in: module).type
    }

    /// The instructions of `function` that `opcode` names, in the order its blocks hold them.
    private func instructions(_ opcode: Opcode, in function: Function) -> [Instruction] {
        function.blocks.flatMap(\.instructions).filter { $0.opcode == opcode }
    }
}
