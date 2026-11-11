import RayoSema
import RayoSyntax
import Testing

struct LayoutTests {
    @Test("a struct's fields lie in memory by decreasing alignment, fields of one alignment in declaration order")
    func layoutOrder() throws {
        let hit = try layout(of: "Hit", in: types("struct Hit(var crit: Bool, var damage: Int, let team: Bool)"))
        #expect(hit.layoutOrder == [1, 0, 2])
        #expect(hit.fieldOffsets == [8, 0, 9])
        #expect(hit.layout == Layout(size: 16, alignment: 8))
    }

    @Test("a struct field is laid out by its own struct's size and alignment, and the size rounds up to the alignment")
    func nested() throws {
        let table = try types("""
            struct Outer(var flag: Bool, var hit: Hit, var count: Int)
            struct Hit(var crit: Bool, var damage: Int, let team: Bool)
            """)

        // `hit`, of 16 bytes aligned to 8, and `count` come before `flag`, which pads the struct to 32.
        let outer = try layout(of: "Outer", in: table)
        #expect(outer.layoutOrder == [1, 2, 0])
        #expect(outer.fieldOffsets == [24, 0, 16])
        #expect(outer.layout == Layout(size: 32, alignment: 8))
    }

    @Test func `a struct of no fields takes no memory, and adds none to the struct that holds it`() throws {
        let table = try types("struct E\nstruct W(var e: E, var b: Bool)\nstruct Bools(var a: Bool, var b: Bool)")
        #expect(try layout(of: "E", in: table).layout == Layout(size: 0, alignment: 1))
        #expect(try layout(of: "W", in: table).layout == Layout(size: 1, alignment: 1))
        #expect(try layout(of: "Bools", in: table).fieldOffsets == [0, 1])
    }

    @Test func `Int and Bool lie in memory as 8 and 1 bytes, each aligned to its size`() throws {
        let table = try types("")
        #expect(table.layout(of: .int) == Layout(size: 8, alignment: 8))
        #expect(table.layout(of: .bool) == Layout(size: 1, alignment: 1))
    }
}

/// The types of the program `declarations` make, after an empty `main`.
private func types(_ declarations: String) throws -> TypeTable {
    let checked = Checker.check(Parser.parse("func main() {}\n" + declarations).file)
    #expect(checked.diagnostics.isEmpty)
    return try #require(checked.program).types
}

/// The layout of the struct `name` among `table`'s structs.
private func layout(of name: String, in table: TypeTable) throws -> StructLayout {
    let index = try #require(table.structs.firstIndex { $0.name == name })
    return table.structLayout(of: StructID(index: index, name: name))
}
