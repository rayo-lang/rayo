@testable import RayoLLVM
import RayoSema
import Testing

@Suite("The LLVM types of values")
struct ValueTypeTests {
    @Test(arguments: [(RayoType.int, UInt32(64)), (RayoType.bool, UInt32(1))])
    func `an Int is held in a 64-bit integer, and a Bool in a 1-bit one`(type: RayoType, width: UInt32) throws {
        try withTypes(of: []) { types in
            #expect(types.llvmType(type).integerWidth == width)
        }
    }

    @Test func `a function that returns nothing returns LLVM's void`() throws {
        try withTypes(of: []) { types in
            #expect(types.llvmType(.void).isVoid)
        }
    }

    @Test func `a struct is held in a packed struct of its fields in layout order, padded at its end`() throws {
        // A Bool, an Int and a Bool lie as the Int, then the Bools, then 6 bytes that pad the struct to 16.
        let pair = StructType(name: "Pair", fields: [
            Field(name: "flag", type: .bool), Field(name: "count", type: .int), Field(name: "other", type: .bool),
        ])

        try withTypes(of: [pair]) { types in
            let llvmType = types.llvmType(.structure(StructID(index: 0, name: "Pair")))
            #expect(llvmType.text == "%Pair = type <{ i64, i1, i1, [6 x i8] }>")
        }
    }

    @Test func `a struct may hold a struct declared after it`() throws {
        let outer = StructType(name: "Outer", fields: [
            Field(name: "inner", type: .structure(StructID(index: 1, name: "Inner"))),
        ])
        let inner = StructType(name: "Inner", fields: [Field(name: "count", type: .int)])

        try withTypes(of: [outer, inner]) { types in
            let llvmType = types.llvmType(.structure(StructID(index: 0, name: "Outer")))
            #expect(llvmType.text == "%Outer = type <{ %Inner }>")
        }
    }

    @Test func `a value is aligned as its type is, a struct as its most-aligned field`() throws {
        let pair = StructType(name: "Pair", fields: [
            Field(name: "flag", type: .bool), Field(name: "count", type: .int),
        ])
        let flags = StructType(name: "Flags", fields: [Field(name: "a", type: .bool), Field(name: "b", type: .bool)])

        try withTypes(of: [pair, flags]) { types in
            #expect(types.alignment(of: .int) == 8)
            #expect(types.alignment(of: .bool) == 1)
            #expect(types.alignment(of: .structure(StructID(index: 0, name: "Pair"))) == 8)
            #expect(types.alignment(of: .structure(StructID(index: 1, name: "Flags"))) == 1)
        }
    }

    /// Runs `body` on the LLVM types of a program whose structs are `structs`, made in a new module for the host.
    private func withTypes(of structs: [StructType], _ body: (LLVMTypes) throws -> Void) throws {
        try withProgramModule(for: .debug) { programModule in
            try body(LLVMTypes(TypeTable(structs: structs), in: programModule.emitter.context))
        }
    }
}
