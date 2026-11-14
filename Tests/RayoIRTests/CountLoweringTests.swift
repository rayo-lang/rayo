import Testing

@Suite("Lowering array counts")
struct CountLoweringTests {
    @Test func `a count is a constant, once its array's place is found and the read of it dropped`() throws {
        // The array lies in an element of a value that no local holds, so the call that gives the value runs, and the
        // index is checked, before the dropped read and the count.
        let source = """
            func main() {
                let a = [1, 2]
                print(a.count)
                print(made()[index()].count)
            }
            func made() -> [2 of [3 of Int]] { [[1, 2, 3], [4, 5, 6]] }
            func index() -> UInt { 1 }
            """
        try expectLowering(of: source, toMatch: "count")
    }
}
