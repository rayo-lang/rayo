import Testing

@Suite("Lowering elements")
struct ElementLoweringTests {
    @Test func `an element is read where it lies, once any index but a literal below the count is checked`() throws {
        // The literal `1` lies below the count, so the IR writes it; `2` lies past the end, so it is checked as any
        // index a value gives is.
        let body = """
            let grid = [[1, 2], [3, 4]]
            let i: UInt = 1
            print(grid[1][0])
            print(grid[i][i - 1])
            print(grid[0][2])
            let row = copy grid[i]
            print(row[0])
            """
        try expectLowering(ofMain: body, toMatch: "element-read")
    }

    @Test func `an element of a value that no local holds is found after the value, then each index in turn`() throws {
        let source = """
            func main() {
                print(made()[index()][index()])
            }
            func made() -> [2 of [2 of Int]] { [[1, 2], [3, 4]] }
            func index() -> UInt { 1 }
            """
        try expectLowering(of: source, toMatch: "element-of-temporary")
    }
}
