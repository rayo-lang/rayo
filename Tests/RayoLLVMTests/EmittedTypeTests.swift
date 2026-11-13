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
            let signature = try signature(of: irFunction.declaration.name, in: module)
            #expect(signature.parameters.map(\.text) == ["i64", "i1"])
            #expect(signature.result.text == resultText)
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
            let llvmFunction = try function(named: irFunction.declaration.name, in: module)
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

    @Test func `a struct is built in its place, each field stored in the element its layout puts it in`() throws {
        // `main` makes a Pair of its Bool and its Int, which the Pair declares in that order.
        let main = mainFunction(locals: [.bool, .int, pairType], [
            BasicBlock(
                statements: [statement(storingIn: 2, .structure(pairID, fields: [read(0), read(1)]))],
                terminator: .return(nil),
            ),
        ])

        // The Bool goes in the second element and the Int in the first, each stored in the Pair's slot.
        try withEmitted(program(of: [main], types: pairTable)) { module in
            let text = try function(named: "rayo.main", in: module).text
            #expect(text.contains("""
                  %3 = getelementptr inbounds nuw %Pair, ptr %2, i32 0, i32 1
                  %4 = load i1, ptr %0, align 1
                  store i1 %4, ptr %3, align 1
                  %5 = getelementptr inbounds nuw %Pair, ptr %2, i32 0, i32 0
                  %6 = load i64, ptr %1, align 8
                  store i64 %6, ptr %5, align 8
                """))
        }
    }

    @Test func `a field is read from the element that its struct's layout puts it in, aligned as its type is`() throws {
        // `main` reads the Pair's Bool, which it declares first.
        let flag = Operand.read(Place(root: LocalID(index: 0), steps: [.field(0)]), at: nowhere)
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

    @Test func `a field inside a field is read by stepping into each struct's element that holds the next`() throws {
        // `main` reads the Bool of the Pair that a Holder declares second.
        let holderTable = TypeTable(structs: pairTable.structs + [
            StructType(name: "Holder", fields: [Field(name: "flag", type: .bool), Field(name: "pair", type: pairType)]),
        ])
        let holderType = RayoType.structure(StructID(index: 1, name: "Holder"))
        let flag = Operand.read(Place(root: LocalID(index: 0), steps: [.field(1), .field(0)]), at: nowhere)
        let main = mainFunction(locals: [holderType, .bool], [
            BasicBlock(statements: [statement(storingIn: 1, .use(flag))], terminator: .return(nil)),
        ])

        // The Holder lays its Pair out first, and the Pair its Bool second, so the read steps into the first element
        // of the one and the second of the other.
        try withEmitted(program(of: [main], types: holderTable)) { module in
            let text = try function(named: "rayo.main", in: module).text
            #expect(text.contains("""
                  %2 = getelementptr inbounds nuw %Holder, ptr %0, i32 0, i32 0
                  %3 = getelementptr inbounds nuw %Pair, ptr %2, i32 0, i32 1
                  %4 = load i1, ptr %3, align 1
                """))
        }
    }

    @Test func `a field is stored in the element that its struct's layout puts it in, aligned as its type is`() throws {
        // `main` stores its Bool in the Pair's Bool, which the Pair declares first.
        let flag = Destination(Place(root: LocalID(index: 0), steps: [.field(0)]), at: nowhere)
        let main = mainFunction(locals: [pairType, .bool], [
            BasicBlock(
                statements: [.compute(destination: flag, value: .use(read(1)), range: nowhere)],
                terminator: .return(nil),
            ),
        ])

        // The store writes one byte to the Pair's second element.
        try withEmitted(program(of: [main], types: pairTable)) { module in
            let text = try function(named: "rayo.main", in: module).text
            #expect(text.contains("""
                  %2 = getelementptr inbounds nuw %Pair, ptr %0, i32 0, i32 1
                  %3 = load i1, ptr %1, align 1
                  store i1 %3, ptr %2, align 1
                """))
        }
    }

    @Test func `a field inside a field is stored by stepping into each struct's element that holds the next`() throws {
        // `main` stores its Int in the Int of the Pair that a Holder declares second.
        let holderTable = TypeTable(structs: pairTable.structs + [
            StructType(name: "Holder", fields: [Field(name: "flag", type: .bool), Field(name: "pair", type: pairType)]),
        ])
        let holderType = RayoType.structure(StructID(index: 1, name: "Holder"))
        let count = Destination(Place(root: LocalID(index: 0), steps: [.field(1), .field(1)]), at: nowhere)
        let main = mainFunction(locals: [holderType, .int], [
            BasicBlock(
                statements: [.compute(destination: count, value: .use(read(1)), range: nowhere)],
                terminator: .return(nil),
            ),
        ])

        // The Holder lays its Pair out first, and the Pair its Int first too, so the store steps into the first
        // element of each.
        try withEmitted(program(of: [main], types: holderTable)) { module in
            let text = try function(named: "rayo.main", in: module).text
            #expect(text.contains("""
                  %2 = getelementptr inbounds nuw %Holder, ptr %0, i32 0, i32 0
                  %3 = getelementptr inbounds nuw %Pair, ptr %2, i32 0, i32 0
                  %4 = load i64, ptr %1, align 8
                  store i64 %4, ptr %3, align 8
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
    private var emptyMain: HandWrittenFunction {
        mainFunction(locals: [], [BasicBlock(statements: [], terminator: .return(nil))])
    }

    /// A function that takes an Int and a Bool, holds `temporaries` besides them, and returns the parameter of type
    /// `result`.
    private func pick(returning result: RayoType, _ temporaries: [IRLocal]) throws -> HandWrittenFunction {
        let parameters: [IRLocal] = [
            .source(name: "n", kind: .parameter, type: .int), .source(name: "b", kind: .parameter, type: .bool),
        ]
        let returned = try #require(parameters.firstIndex { $0.type == result })
        return handWritten(
            name: "pick(_: Int, _: Bool)", parameterCount: 2, result: result, locals: parameters + temporaries,
            blocks: [BasicBlock(statements: [], terminator: .return(read(returned)))],
        )
    }

    /// The type of the function named `name` in `module`: its parameters and its result.
    private func signature(of name: String, in module: borrowing Module) throws -> FunctionType {
        try function(named: name, in: module).type
    }
}
