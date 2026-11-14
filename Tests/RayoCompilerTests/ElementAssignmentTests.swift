import Testing
import RayoDiagnostics

/// Structs that hold arrays, in a `var` field and in a `let` one, and functions that make an array and borrow an Int,
/// which the bodies below use.
private let declarations = """
    struct Stats(var hp: Int)
    struct Enemy(var slots: [2 of Int], let fixed: [2 of Int])
    func made() -> [2 of Int] { [1, 2] }
    func take(_ n: Int) {}
    func total(_ a: [2 of Int]) -> Int { a[0] + a[1] }
    """

/// The errors that `body`, as the body of a function that borrows the array `p`, reports, each as its position, code
/// and message. The body starts on line 3.
private func errorLines(_ body: String) -> [String] {
    diagnostics("func main() {}\nfunc f(_ p: [2 of Int]) {\n\(body)\n}\n\(declarations)").map(\.description)
}

struct ElementAssignmentTests {
    @Test(arguments: [
        "var a = [1, 2]\na[0] = 3\na[1] += a[0]\ntake(a[1])",
        "var a = [1, 2]\nlet i: UInt = 1\na[i] = 3\na[i - 1] -= 1\ntake(a[0] + a[i])",
        "var e = Enemy(slots: [1, 2], fixed: [3, 4])\ne.slots[1] = 5\ne.slots[0] *= 2\ntake(e.slots[0] + e.slots[1])",
        "var grid = [[1, 2], [3, 4]]\ngrid[1][0] = 5\ngrid[0] = [6, 7]\ntake(grid[0][1] + grid[1][0] + grid[1][1])",
        "var a = [Stats(hp: 1), Stats(hp: 2)]\nlet s = Stats(hp: 3)\na[0] = s\na[0].hp += 1\ntake(a[0].hp + a[1].hp)",
        "var a = [Stats(hp: 1), Stats(hp: 2)]\na[0] = copy a[1]\ntake(a[0].hp)",
        "var a = [1, 2]\na[0] = 5\nlet b = a\ntake(b[0])",
        "var a = [1, 2]\nlet i: UInt = 1\na[i] = 5\ntake(total(a))",
        "var a = [1, 2]\na[1] += 5\ntake(total(a))",
        "var e = Enemy(slots: [1, 2], fixed: [3, 4])\ne.slots[0] = 5\nlet t = e\ntake(t.slots[0])",
        "var grid = [[1, 2], [3, 4]]\ngrid[0][1] = 5\ntake(total(grid[0]) + total(grid[1]))",
    ])
    func `an element of a 'var' place is assigned a value of its type`(body: String) {
        #expect(errorLines(body) == [])
    }

    @Test(arguments: [
        ("let a = [1, 2]\na[0] = 3", "4:1: error[E0251]: 'a' is a 'let', so its fields and elements can't change"),
        (
            "let a = [[1, 2]]\na[0][1] += 3",
            "4:1: error[E0251]: 'a' is a 'let', so its fields and elements can't change",
        ),
        (
            "var e = Enemy(slots: [1, 2], fixed: [3, 4])\ne.fixed[0] = 1",
            "4:3: error[E0252]: 'fixed' is a 'let' field, so it can't change",
        ),
        ("p[0] = 1", "3:1: error[E0230]: 'p' is a borrowed parameter, so it can't change"),
        ("p[1] -= 1", "3:1: error[E0230]: 'p' is a borrowed parameter, so it can't change"),
        ("made()[0] = 1", "3:1: error[E0223]: only a local, or a field or element of one, can be assigned"),
    ])
    func `an element is assigned only where a field would be`(body: String, expected: String) {
        #expect(errorLines(body) == [expected])
    }

    @Test(arguments: [
        ("var a: [2 of Int]\na[0] = 1\ntake(a[0])", "4:1: error[E0304]: 'a' isn't initialized"),
        ("var a: [2 of Int]\na[0] += 1\ntake(a[0])", "4:1: error[E0304]: 'a' isn't initialized"),
        ("var a = [1, 2]\nlet b = a\na[0] = 1\ntake(a[0])", "5:1: error[E0302]: 'a' was moved"),
        (
            "var e = Enemy(slots: [1, 2], fixed: [3, 4])\nlet s = e.slots\ne.slots[0] = 1\ntake(e.slots[0])",
            "5:1: error[E0302]: 'e.slots' was moved",
        ),
    ])
    func `an element is assigned only in an array that holds a value`(body: String, expected: String) {
        #expect(errorLines(body) == [expected])
    }

    @Test(arguments: [
        (
            "var a = [Stats(hp: 1)]\nlet s = Stats(hp: 2)\na[0] = s\ntake(s.hp)",
            "6:6: error[E0302]: 's' was moved",
        ),
        (
            "var a = [Stats(hp: 1), Stats(hp: 2)]\na[0] = a[1]\ntake(a[0].hp)",
            "4:8: error[E0315]: an array's element can't be moved, nor any part of one; 'copy' makes an owned copy",
        ),
        ("var a = [1, 2]\na[0] = 3\ntake(a[1])", "4:1: error[E0308]: the value assigned to 'a[0]' is never read"),
        (
            "var a = [1, 2]\na[0] = 3\na[0] = 4\ntake(total(a))",
            "4:1: error[E0308]: the value assigned to 'a[0]' is never read",
        ),
    ])
    func `an element takes the value it is assigned, which some code reads`(body: String, expected: String) {
        #expect(errorLines(body) == [expected])
    }
}
