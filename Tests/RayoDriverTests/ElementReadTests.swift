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
}
