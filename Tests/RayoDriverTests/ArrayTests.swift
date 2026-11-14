import Testing
import RayoDriver

struct ArrayTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `arrays of Ints, Bools, structs and arrays are built, passed, returned, stored, moved and copied`(
        mode: [String],
    ) {
        // Each array is made by a literal, then passed to a borrowed parameter, returned, stored in a local or a
        // field, moved and copied, small ones in their scalars and large ones in their places. A call that returns
        // what it is given prints a count, so the run shows each call ran.
        let source = """
            func main() {
                let ints: [2 of Int] = [1, -2]
                let kept = relayInts(ints)
                let bools = [true, false, true]
                let copied = copy bools
                let returned = relayBools(bools)
                let hits = [Hit(damage: 3), Hit(damage: 4)]
                let grid = [[1, 2, 3], [4, 5, 6]]
                var board = Board(grid: grid, hits: hits, flags: copied)
                let moved = board.grid
                board.grid = relayGrid(moved)
                let none: [0 of Int] = []
                _ = relayNone(none)
                _ = relayNone([])
                print(count(of: board, kept, returned))
            }
            func relayInts(_ a: [2 of Int]) -> [2 of Int] { copy a }
            func relayBools(_ a: [3 of Bool]) -> [3 of Bool] {
                print(3)
                return copy a
            }
            func relayGrid(_ a: [2 of [3 of Int]]) -> [2 of [3 of Int]] {
                print(6)
                let b = copy a
                return b
            }
            func relayNone(_ a: [0 of Int]) -> [0 of Int] {
                print(0)
                return copy a
            }
            func count(of board: Board, _ ints: [2 of Int], _ bools: [3 of Bool]) -> Int { 7 }
            struct Hit(var damage: Int)
            struct Board(var grid: [2 of [3 of Int]], let hits: [2 of Hit], var flags: [3 of Bool])
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "3\n6\n0\n0\n7\n", errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `arrays of a hundred thousand elements pass and return, and their program builds and runs`(mode: [String]) {
        let source = """
            func main() { print(1) }
            func relay(_ a: [100000 of Int]) -> [100000 of Int] { copy a }
            func relayAll(_ a: [100000 of [2 of Hit]]) -> [100000 of [2 of Hit]] { relay(copy a) }
            func relay(_ a: [100000 of [2 of Hit]]) -> [100000 of [2 of Hit]] { copy a }
            struct Hit(var damage: Int, let crit: Bool)
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "1\n", errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]], [
        ("let a: [3 of Int] = [1, 2]", "2:25: error[E0261]: a [3 of Int] literal needs 3 elements, found 2"),
        ("let a = []", "2:13: error[E0262]: an empty array literal needs a type"),
        ("let a = [1, true]", "2:14: error[E0263]: the array literal holds Bool in one element and Int in another"),
        ("var a: [2 of ()]", "2:18: error[E0264]: an array's elements can't have type Void"),
        ("var a: [2305843009213693952 of Int]", "2:12: error[E0265]: the array's size in bytes doesn't fit in an Int"),
    ])
    func `an array that can't be laid out, or a literal that doesn't fit its type, is an error, in debug and release`(
        mode: [String], failure: (body: String, error: String),
    ) {
        let source = "func main() {\n    \(failure.body)\n}"
        let expected = CommandResult(exitCode: 1, output: "", errors: "main.rayo:\(failure.error)\n")
        #expect(run(source, options: mode) == expected)
    }
}

/// A function that prints each element of an array of three Ints, which the programs below use.
private let show = """

    func show(_ a: [3 of Int]) {
        var i: UInt = 0
        while i < a.count {
            print(a[i])
            i += 1
        }
    }
    """

struct FilledArrayTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `.init(all:) fills arrays of Ints, Bools, structs and arrays wherever an array type is expected`(
        mode: [String],
    ) {
        // Each array is filled where a local's annotation, an argument, a `return`, an assignment, a field's argument
        // or an outer array expects it, and each of its elements is printed. `relayFlags` and `made` each print their
        // array's count as they run, so the run shows each was called.
        let source = """
            func main() {
                var ints: [3 of Int] = .init(all: 7)
                show(ints)
                ints = .init(all: -1)
                show(ints)
                let flags = relayFlags(.init(all: true))
                print(flags[0])
                print(flags[1])
                let hit = Hit(damage: 3)
                let board = Board(hits: .init(all: hit), grid: [.init(all: 1), [2, 3]])
                print(board.hits[0].damage)
                print(board.hits[1].damage)
                print(board.grid[0][0])
                print(board.grid[0][1])
                let grids: [2 of [2 of [3 of Int]]] = .init(all: .init(all: .init(all: 5)))
                var i: UInt = 0
                while i < grids.count {
                    show(grids[i][0])
                    show(grids[i][1])
                    i += 1
                }
                let none: [0 of Hit] = .init(all: hit)
                print(none.count)
                let filled = made()
                var j: UInt = 0
                while j < filled.count {
                    print(filled[j].damage)
                    j += 1
                }
                print(hit.damage)
            }
            func relayFlags(_ a: [2 of Bool]) -> [2 of Bool] {
                print(2)
                return copy a
            }
            func made() -> [4 of Hit] {
                print(4)
                return .init(all: Hit(damage: 9))
            }
            struct Hit(var damage: Int)
            struct Board(let hits: [2 of Hit], var grid: [2 of [2 of Int]])
            """ + show
        let expected = "7\n7\n7\n-1\n-1\n-1\n2\ntrue\ntrue\n3\n3\n1\n1\n" + String(repeating: "5\n", count: 12)
            + "0\n4\n9\n9\n9\n9\n3\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: expected, errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `the value is evaluated once, even for an array of no elements`(mode: [String]) {
        // Each value prints its number as it is evaluated, before the filled arrays' elements are printed.
        let source = """
            func main() {
                let a: [3 of Int] = .init(all: next(1))
                let b: [0 of Int] = .init(all: next(2))
                let c: [2 of [3 of Int]] = .init(all: .init(all: next(3)))
                print(b.count)
                show(a)
                show(c[0])
                show(c[1])
            }
            func next(_ n: Int) -> Int {
                print(n)
                return copy n
            }
            """ + show
        let expected = "1\n2\n3\n0\n1\n1\n1\n3\n3\n3\n3\n3\n3\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: expected, errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `changing one element of a filled array leaves the others holding the value`(mode: [String]) {
        let source = """
            func main() {
                var a: [3 of Int] = .init(all: 7)
                a[1] = 8
                show(a)
                var grid: [2 of [3 of Int]] = .init(all: .init(all: 1))
                grid[1][2] += 5
                show(grid[0])
                show(grid[1])
                var hits: [2 of Hit] = .init(all: Hit(damage: 3))
                hits[0].damage = 4
                print(hits[0].damage)
                print(hits[1].damage)
            }
            struct Hit(var damage: Int)
            """ + show
        let expected = "7\n8\n7\n1\n1\n1\n1\n1\n6\n4\n3\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: expected, errors: ""))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [["--debug"], ["--release"]])
    func `an array of a hundred thousand elements is filled, and its program builds quickly and runs`(mode: [String]) {
        let source = """
            func main() {
                var a: [100000 of Int] = .init(all: 0)
                print(a[0] + a[99999])
                a = .init(all: 1)
                let hits: [1000 of [100 of Hit]] = .init(all: .init(all: Hit(damage: 2, crit: true)))
                print(a[0] + a[99999])
                print(hits[0][0].damage + hits[999][99].damage)
            }
            struct Hit(var damage: Int, let crit: Bool)
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "0\n2\n4\n", errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]], [
        ("let a = .init(all: 0)", "2:13: error[E0267]: the implicit member '.init' needs a type"),
        ("let a: [2 of Int] = .init(each: 0)", "2:25: error[E0268]: '.init(each:)' isn't supported"),
        ("let a: [2 of Int] = .init(al: 0)", "2:31: error[E0228]: expected 'all:' before the argument, found 'al:'"),
    ])
    func `.init(all:) with no array type, or with the wrong member or label, is an error, in debug and release`(
        mode: [String], failure: (body: String, error: String),
    ) {
        let source = "func main() {\n    \(failure.body)\n}"
        let expected = CommandResult(exitCode: 1, output: "", errors: "main.rayo:\(failure.error)\n")
        #expect(run(source, options: mode) == expected)
    }
}
