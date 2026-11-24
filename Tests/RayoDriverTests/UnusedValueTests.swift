import Testing
import RayoDriver

struct UnusedValueTests {
    @Test("'_ =' drops a value on purpose, which is still computed")
    func dropped() {
        let source = """
            func main() {
                _ = say(1)
                _ = print(2)
                let x = 3
                _ = copy x
            }
            func say(_ x: Int) -> Int {
                print(x)
                return copy x
            }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "1\n2\n", errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `'_ = copy' drops a copy of a struct or an array and leaves it whole, and '_ = consume' drops it`(
        mode: [String],
    ) {
        let source = """
            func main() {
                let boss = Enemy(hp: 7, slots: [8, 9])
                _ = copy boss
                print(boss.hp)
                print(boss.slots[1])
                _ = consume boss
                let grid = [[1, 2], [3, 4]]
                _ = copy grid
                print(grid[1][0])
                _ = consume grid
            }
            struct Enemy(var hp: Int, var slots: [2 of Int])
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "7\n9\n3\n", errors: ""))
    }
}
