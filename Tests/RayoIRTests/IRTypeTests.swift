import RayoIR
import RayoSema
import Testing

@Suite("The types of IR values")
struct IRTypeTests {
    @Test func `an operation's value and an operand's are of the types their source's expressions are`() throws {
        let program = try lowered("""
            struct Pair(var count: Int, var flag: Bool)
            func twice(_ n: Int) -> Int { n * 2 }
            func main() {
                let pair = Pair(count: -twice(3), flag: !(1 < 2))
                print(pair.count % 4 == 1)
            }
            """)
        let main = program.body(at: try #require(program.main).index)
        let pair = RayoType.structure(StructID(index: 0, name: "Pair"))

        // Each computation in `main`, in order, and the type of the value it makes.
        let values = main.blocks.flatMap(\.statements).compactMap { statement -> Rvalue? in
            guard case .compute(_, let value, _) = statement else { return nil }
            return value
        }
        let valueTypes = values.map { $0.type(in: main, types: program.types, functions: program.functions) }
        #expect(valueTypes == [.int, .int, .bool, .bool, pair, .int, .bool, .void])

        // A read of a field is of the field's type.
        #expect(read(0, fields: 1).type(in: main, types: program.types) == .bool)
    }
}
