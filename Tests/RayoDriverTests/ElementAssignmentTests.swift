import Testing
import RayoDriver

/// A struct, another that holds arrays of Ints and of the first, and a function that reads a whole array, which the
/// programs below use.
private let declarations = """

    struct Stats(var hp: Int)
    struct Enemy(var slots: [2 of Int], var party: [2 of Stats])
    func total(_ a: [2 of Int]) -> Int { a[0] + a[1] }
    """

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
            """ + declarations
        let expected = "24\n9\n1\n65\n150\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: expected, errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `elements of locals, fields, nested arrays and arrays of structs change in place`(mode: [String]) {
        let source = """
            func main() {
                var a = [10, 20, 30]
                let i: UInt = 2
                a[0] += 1
                a[i] *= 3
                print(a[0])
                print(a[i])
                var grid = [[1, 2], [3, 4]]
                grid[1][0] -= 9
                grid[i - 1][1] %= 3
                print(grid[1][0])
                print(grid[1][1])
                var party = [Stats(hp: 7), Stats(hp: 8)]
                party[i - 1].hp -= 5
                print(party[1].hp)
                var e = Enemy(slots: [5, 6], party: [Stats(hp: 7), Stats(hp: 8)])
                e.slots[1] /= 2
                e.party[0].hp += e.slots[1]
                print(e.slots[1])
                print(e.party[0].hp)
            }
            """ + declarations
        let expected = "11\n90\n-6\n1\n3\n3\n10\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: expected, errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `an array read whole after an element changes holds the new element beside the others`(mode: [String]) {
        let source = """
            func main() {
                var a = [1, 2]
                let i: UInt = 1
                a[0] = 5
                let b = a
                print(total(b))
                var c = [1, 2]
                c[i] = 7
                print(total(c))
                var d = [1, 2]
                d[i] += 10
                print(total(d))
                var e = Enemy(slots: [1, 2], party: [Stats(hp: 3), Stats(hp: 4)])
                e.slots[0] = 9
                e.party[i].hp = 40
                let f = e
                print(total(f.slots))
                print(f.party[0].hp + f.party[1].hp)
                var grid = [[1, 2], [3, 4]]
                grid[0][1] = 20
                print(total(grid[0]) + total(grid[1]))
            }
            """ + declarations
        let expected = "7\n8\n13\n11\n43\n28\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: expected, errors: ""))
    }
}

struct ElementAssignmentOrderTests {
    /// Each index and each value is a call that prints the number it gives, so a run shows how often and in what
    /// order each runs.
    private static let numbers = """

        func index(_ i: UInt) -> UInt {
            print(i)
            return copy i
        }
        func value(_ v: Int) -> Int {
            print(v)
            return copy v
        }
        """

    @Test(arguments: [["--debug"], ["--release"]], ["=", "+="])
    func `an assignment finds its place, each index once, before it evaluates its value`(
        mode: [String], assign: String,
    ) {
        let source = """
            func main() {
                var grid = [[1, 2], [3, 4]]
                grid[index(1)][index(0)] \(assign) value(10)
                print(grid[1][0])
            }
            """ + Self.numbers
        let result = assign == "=" ? 10 : 13
        let expected = CommandResult(exitCode: 0, output: "1\n0\n10\n\(result)\n", errors: "")
        #expect(run(source, options: mode) == expected)
    }

    @Test(arguments: [["--debug"], ["--release"]], ["=", "-="])
    func `an index past the array's end panics before the value is evaluated or stored`(
        mode: [String], assign: String,
    ) {
        let source = """
            func main() {
                var grid = [[1, 2], [3, 4]]
                grid[index(0)][index(2)] \(assign) value(10)
                print(grid[1][0])
            }
            """ + Self.numbers
        let expected = CommandResult(exitCode: 101, output: "0\n2\n",
                                     errors: "main.rayo:3:20: panic: index out of range\n")
        #expect(run(source, options: mode) == expected)
    }
}
