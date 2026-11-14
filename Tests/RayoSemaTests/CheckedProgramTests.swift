import RayoSema
import RayoSyntax
import SnapshotTesting
import Testing

/// Parses and checks `source`, and expects the checked program's text to be the snapshot `name.checked`.
private func expectChecking(
    of source: String, toMatch name: String, sourceLocation: Testing.SourceLocation = #_sourceLocation,
) throws {
    let (file, syntaxErrors) = Parser.parse(source)
    try #require(syntaxErrors.isEmpty, "\(syntaxErrors)", sourceLocation: sourceLocation)
    let (program, checkErrors) = Checker.check(file)
    try #require(checkErrors.isEmpty, "\(checkErrors)", sourceLocation: sourceLocation)
    Snapshot("\(name).checked").expect(CheckedPrinter.text(of: program), sourceLocation: sourceLocation)
}

@Suite("The checked program of each construct")
struct CheckedProgramTests {
    @Test func `a function's parameters are its first locals, and a call names the function it resolves to`() throws {
        try expectChecking(of: """
            func main() {
                print(add(1, to: 2))
                print(isZero(0))
                greet()
            }
            func add(_ a: Int, to b: Int) -> Int { a + b }
            func isZero(_ n: Int) -> Bool {
                return n == 0
            }
            func greet() {
                return
            }
            """, toMatch: "functions")
    }

    @Test func `each operator on Ints and Bools has the type of its value`() throws {
        try expectChecking(of: """
            func main() {
                let a = 7
                let b = 2
                print(a + b * a - b / a % b)
                print(-a)
                print(a == b && a != b || a < b)
                print(a <= b || a > b && a >= b)
                let t = true
                print(!t)
            }
            """, toMatch: "operators")
    }

    @Test func `a local is a 'let' or a 'var', and an assignment names the place it stores in`() throws {
        try expectChecking(of: """
            func main() {
                let x = 1
                var y: Int
                y = x
                y += 2
                y -= 1
                y *= 3
                print(y)
            }
            """, toMatch: "locals")
    }

    @Test func `an 'if' is a statement or a value, and a loop's 'break' and 'continue' are statements`() throws {
        try expectChecking(of: """
            func main() {
                var i = 0
                let c = true
                if c { print(1) } else { print(2) }
                let y = if c { 1 } else { 2 }
                while i < y {
                    i += 1
                    if i == 1 { continue }
                    break
                }
            }
            """, toMatch: "control-flow")
    }

    @Test func `checking leaves a local written bare as its value, and a 'copy' of it as a copy`() throws {
        try expectChecking(of: """
            func main() {
                let a = 1
                let b = copy a
                let c = a
                print(b + c)
            }
            """, toMatch: "places")
    }

    @Test func `a struct is made by its primary initializer, and a field is a place in a local or temporary`() throws {
        try expectChecking(of: """
            struct Shot(let range: Int, var hit: Hit)
            struct Hit(var damage: Int)
            func main() {
                let damage = 7
                var s = Shot(range: 4, hit: Hit(damage: damage))
                s.hit.damage = 9
                print(s.range)
                let h = s.hit
                print(h.damage)
                print(Hit(damage: 3).damage)
            }
            """, toMatch: "structs")
    }

    @Test func `an element is a place that names its array's count, and holds its index, a literal as a UInt`() throws {
        try expectChecking(of: """
            struct Hit(var damage: Int)
            func main() {
                let hits = [[Hit(damage: 1)], [Hit(damage: 2)]]
                let i: UInt = 1
                print(hits[i][0].damage)
                let h = copy hits[0][i - 1]
                print(h.damage)
            }
            """, toMatch: "elements")
    }

    @Test func `a count holds the place of the array it counts, and roots a place that goes on from it`() throws {
        try expectChecking(of: """
            func main() {
                let grid = [[1, 2, 3], [4, 5, 6]]
                let i: UInt = 1
                print(grid.count)
                print(grid[i].count)
                let n = copy grid.count
                print(n)
            }
            """, toMatch: "counts")
    }
}
