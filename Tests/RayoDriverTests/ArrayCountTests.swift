import Testing
import RayoDriver

struct ArrayCountTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `an array's count is the length its type gives, wherever the array lies`(mode: [String]) {
        // Each position prints the count of an array of 0 elements after one of more. The calls that make arrays print
        // 7, so the run shows each call runs though no code loads its array.
        let source = """
            func main() {
                let a = [10, 20, 30]
                let none: [0 of Int] = []
                print(a.count)
                print(none.count)
                print(length(of: a))
                print(lengthOfNone(none))
                let e = Enemy(slots: [5, 6], none: [])
                print(e.slots.count)
                print(e.none.count)
                let grid = [[1, 2, 3, 4], [5, 6, 7, 8]]
                let empties: [2 of [0 of Int]] = [[], []]
                let i: UInt = 1
                print(grid.count)
                print(grid[i].count)
                print(empties[i].count)
                print(make().count)
                print(makeNone().count)
            }
            func length(of a: [3 of Int]) -> UInt { a.count }
            func lengthOfNone(_ a: [0 of Int]) -> UInt { a.count }
            func make() -> [5 of Bool] {
                print(7)
                return [true, true, false, false, true]
            }
            func makeNone() -> [0 of Bool] {
                print(7)
                return []
            }
            struct Enemy(var slots: [2 of Int], var none: [0 of Int])
            """
        let expected = "3\n0\n3\n0\n2\n0\n2\n4\n0\n7\n5\n7\n0\n"
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
