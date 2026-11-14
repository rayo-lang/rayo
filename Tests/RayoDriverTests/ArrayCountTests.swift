import Testing
import RayoDriver

struct ArrayCountTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `an array's count is the length its type gives, wherever the array lies`(mode: [String]) {
        // The call that makes an array prints 7, so the run shows the call runs though its array is never read.
        let source = """
            func main() {
                let a = [10, 20, 30]
                print(a.count)
                let none: [0 of Int] = []
                print(none.count)
                print(length(of: a))
                let e = Enemy(slots: [5, 6])
                print(e.slots.count)
                let grid = [[1, 2, 3, 4], [5, 6, 7, 8]]
                let i: UInt = 1
                print(grid.count)
                print(grid[i].count)
                print(make().count)
            }
            func length(of a: [3 of Int]) -> UInt { a.count }
            func make() -> [5 of Bool] {
                print(7)
                return [true, true, false, false, true]
            }
            struct Enemy(var slots: [2 of Int])
            """
        let expected = "3\n0\n3\n2\n2\n4\n7\n5\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: expected, errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `a loop runs a UInt counter up to an array's count`(mode: [String]) {
        let source = """
            func main() {
                let a = [3, 4, 5]
                var i: UInt = 0
                var sum = 0
                while i < a.count {
                    sum += a[i]
                    i += 1
                }
                print(sum)
            }
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "12\n", errors: ""))
    }
}
