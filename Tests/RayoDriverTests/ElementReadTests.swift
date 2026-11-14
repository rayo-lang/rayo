import Testing
import RayoDriver

struct ElementReadTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `elements of locals, parameters, fields and nested arrays are read where they lie`(mode: [String]) {
        let source = """
            func main() {
                let a = [10, 20, 30]
                let i: UInt = 2
                print(a[0])
                print(a[i])
                print(a[i - 1] + a[0])
                let grid = [[1, 2], [3, 4]]
                print(grid[1][0])
                let e = Enemy(slots: [5, 6], party: [Stats(hp: 7), Stats(hp: 8)])
                print(e.slots[1])
                print(e.party[i - 1].hp)
                print(sum(a))
                if a[1] > 15 { print(true) }
            }
            func sum(_ a: [3 of Int]) -> Int { a[0] + a[1] + a[2] }
            struct Stats(var hp: Int)
            struct Enemy(var slots: [2 of Int], var party: [2 of Stats])
            """
        let expected = "10\n30\n30\n3\n6\n8\n60\ntrue\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: expected, errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `a copy of an element, or of a field inside one, is the reader's own`(mode: [String]) {
        let source = """
            func main() {
                var party = [Stats(hp: 7), Stats(hp: 8)]
                let i: UInt = 1
                var first = copy party[0]
                first.hp += 63
                let hp = copy party[i].hp
                print(first.hp)
                print(hp)
                print(party[0].hp)
                print(last(of: party, at: i))
            }
            func last(of party: [2 of Stats], at i: UInt) -> Int { copy party[i].hp }
            struct Stats(var hp: Int)
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "70\n8\n7\n8\n", errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `an index past the array's end panics where the source writes the index`(mode: [String]) {
        let source = """
            func main() {
                let grid = [[1, 2], [3, 4]]
                let i: UInt = 2
                print(grid[0][1])
                print(grid[1][i])
            }
            """
        let expected = CommandResult(exitCode: 101, output: "2\n",
                                     errors: "main.rayo:5:19: panic: index out of range\n")
        #expect(run(source, options: mode) == expected)
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `each index is found once, left to right, and checked before the next is found`(
        mode: [String],
    ) {
        // Each index is a call that prints the index it gives, so the run shows how often and in what order each
        // runs, and that the second never runs once the first is out of range.
        let source = """
            func main() {
                let grid = [[1, 2], [3, 4]]
                print(grid[index(1)][index(0)])
                print(grid[index(2)][index(0)])
            }
            func index(_ i: UInt) -> UInt {
                print(i)
                return copy i
            }
            """
        let expected = CommandResult(exitCode: 101, output: "1\n0\n3\n2\n",
                                     errors: "main.rayo:4:16: panic: index out of range\n")
        #expect(run(source, options: mode) == expected)
    }
}
