import RayoSema
import RayoSyntax
import Testing

/// The types of the program `declarations` make, after an empty `main`.
private func types(_ declarations: String) -> TypeTable {
    let checked = Checker.check(Parser.parse("func main() {}\n" + declarations).file)
    #expect(checked.diagnostics.isEmpty)
    return checked.program!.types
}

/// The layout of the struct `name` among `table`'s structs.
private func layout(of name: String, in table: TypeTable) -> StructLayout {
    let index = table.structs.firstIndex { $0.name == name }!
    return table.layout(of: StructID(index: index, name: name))
}

struct LayoutTests {
    @Test("a struct's fields lie in memory by decreasing alignment, fields of one alignment in declaration order")
    func fieldOrder() {
        let hit = layout(of: "Hit", in: types("struct Hit(var crit: Bool, var damage: Int, let team: Bool)"))
        #expect(hit.fieldOrder == [1, 0, 2])
        #expect(hit.fieldOffsets == [8, 0, 9])
        #expect(hit.layout == Layout(size: 16, alignment: 8))
    }

    @Test("a struct field is laid out by its own struct's size and alignment, and the size rounds up to the alignment")
    func nested() {
        let table = types("""
            struct Outer(var flag: Bool, var hit: Hit, var count: Int)
            struct Hit(var crit: Bool, var damage: Int, let team: Bool)
            """)
        let outer = layout(of: "Outer", in: table)
        #expect(outer.fieldOrder == [1, 2, 0])
        #expect(outer.fieldOffsets == [24, 0, 16])
        #expect(outer.layout == Layout(size: 32, alignment: 8))
    }

    @Test("a struct of no fields takes no memory, and adds none to the struct that holds it")
    func empty() {
        let table = types("struct E\nstruct W(var e: E, var b: Bool)\nstruct Bools(var a: Bool, var b: Bool)")
        #expect(layout(of: "E", in: table).layout == Layout(size: 0, alignment: 1))
        #expect(layout(of: "W", in: table).layout == Layout(size: 1, alignment: 1))
        #expect(layout(of: "Bools", in: table).fieldOffsets == [0, 1])
    }

    @Test("Int and Bool lie in memory as 8 and 1 bytes, each aligned to its size")
    func scalars() {
        let table = types("")
        #expect(table.layout(of: .int) == Layout(size: 8, alignment: 8))
        #expect(table.layout(of: .bool) == Layout(size: 1, alignment: 1))
    }
}
