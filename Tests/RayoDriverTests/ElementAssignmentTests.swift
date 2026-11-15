import Testing
import RayoDriver

struct ElementAssignmentTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `elements of locals, fields, nested arrays and arrays of structs are assigned where they lie`(
        mode: [String],
    ) {
        let source = """
            func main() {
                var a = [10, 20, 30]
                let i: UInt = 2
                a[0] = 1
                a[i] = 3
                print(a[0] + a[1] + a[i])
                var grid = [[1, 2], [3, 4]]
                grid[1][0] = 9
                grid[i - 1][1] = copy grid[0][0]
                print(grid[1][0])
                print(grid[1][1])
                var e = Enemy(slots: [5, 6], party: [Stats(hp: 7), Stats(hp: 8)])
                e.slots[1] = 60
                e.party[i - 1].hp = 80
                e.party[0] = Stats(hp: 70)
                print(e.slots[0] + e.slots[1])
                print(e.party[0].hp + e.party[1].hp)
            }
            struct Stats(var hp: Int)
            struct Enemy(var slots: [2 of Int], var party: [2 of Stats])
            """
        let expected = "24\n9\n1\n65\n150\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: expected, errors: ""))
    }
}
