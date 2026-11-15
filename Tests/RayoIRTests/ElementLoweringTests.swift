import Testing

@Suite("Lowering elements")
struct ElementLoweringTests {
    @Test func `an element is read where it lies, once any index but a literal is checked`() throws {
        // A literal index lies below the count, since checking reports one that doesn't, so the IR writes it; an
        // index a value gives is checked.
        let body = """
            let grid = [[1, 2], [3, 4]]
            let i: UInt = 1
            print(grid[1][0])
            print(grid[i][i - 1])
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

    @Test func `an element is assigned where it lies, each index found and checked before the value it takes`() throws {
        // A compound assignment reads the element it changes, and a bare local it takes is moved into the element.
        let source = """
            func main() {
                var a = [1, 2]
                var e = Enemy(slots: [3, 4])
                let x = 5
                a[index()] = value()
                a[0] += 1
                e.slots[index()] = x
                print(a[0] + e.slots[1])
            }
            struct Enemy(var slots: [2 of Int])
            func index() -> UInt { 1 }
            func value() -> Int { 6 }
            """
        try expectLowering(of: source, toMatch: "element-assignment")
    }

    @Test func `an element in a position that takes its value is moved out of its array, as a bare local is`() throws {
        try expectLowering(ofMain: "let a = [1, 2]\nlet b = a[0]", toMatch: "element-move")
    }

    @Test func `a field of an element, or an element of an element, that a statement takes is moved where it lies`()
        throws {
        let source = """
            func main() {
                let a = [Stats(hp: 1)]
                let i: UInt = 0
                let x = a[i].hp
                let grid = [[1, 2]]
                _ = grid[0][1]
            }
            struct Stats(var hp: Int)
            """
        try expectLowering(of: source, toMatch: "element-part-move")
    }

    @Test func `a compound assignment finds each index of its element once, before it evaluates its value`() throws {
        let source = """
            func main() {
                var grid = [[1, 2], [3, 4]]
                grid[index()][index()] += value()
                print(grid[1][0])
            }
            func index() -> UInt { 1 }
            func value() -> Int { 6 }
            """
        try expectLowering(of: source, toMatch: "compound-element-assignment")
    }

    @Test func `an element of an element is assigned where it lies`() throws {
        let body = "var grid = [[1, 2], [3, 4]]\ngrid[0][1] = 5\nprint(grid[0][1])"
        try expectLowering(ofMain: body, toMatch: "nested-element-assignment")
    }
}
