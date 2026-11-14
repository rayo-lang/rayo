import Testing
import RayoDiagnostics

/// A struct that holds an array, and functions that give an index and borrow an Int, which the bodies below use.
private let declarations = """
    struct Enemy(var slots: [2 of Int])
    func five() -> UInt { 5 }
    func take(_ n: Int) {}
    """

/// The errors that `body`, as `main`'s body beside `declarations`, reports, each as its position, code and message.
/// The body starts on line 2.
private func errorLines(_ body: String) -> [String] {
    diagnostics("func main() {\n\(body)\n}\n\(declarations)").map(\.description)
}

struct IndexBoundsTests {
    @Test(arguments: [
        ("let a = [1, 2, 3]\ntake(a[3])", "3:8: error[E0274]: index 3 is out of range for a [3 of Int]"),
        ("let a = [1, 2, 3]\nlet x = copy a[5]\ntake(x)", "3:16: error[E0274]: index 5 is out of range for a [3 of Int]"),
        ("var a = [1, 2, 3]\na[3] = 4\ntake(a[0])", "3:3: error[E0274]: index 3 is out of range for a [3 of Int]"),
        ("var a = [1, 2, 3]\na[7] += 4\ntake(a[0])", "3:3: error[E0274]: index 7 is out of range for a [3 of Int]"),
        (
            "var e = Enemy(slots: [1, 2])\ne.slots[2] = 4\ntake(e.slots[0])",
            "3:9: error[E0274]: index 2 is out of range for a [2 of Int]",
        ),
        (
            "let grid = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]\ntake(grid[0][7])",
            "3:14: error[E0274]: index 7 is out of range for a [3 of Int]",
        ),
        (
            "var grid = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]\ngrid[3][0] -= 1\ntake(grid[0][0])",
            "3:6: error[E0274]: index 3 is out of range for a [3 of [3 of Int]]",
        ),
    ])
    func `an integer literal index outside the array is an error, read or assigned, at any depth`(
        body: String, expected: String,
    ) {
        #expect(errorLines(body) == [expected])
    }

    @Test(arguments: [
        "let a = [1, 2, 3]\ntake(a[0])\ntake(a[2])",
        "var grid = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]\ngrid[2][2] = 0\ntake(grid[0][0] + grid[2][2])",
        "let a = [1, 2, 3]\nlet i: UInt = 5\ntake(a[i])",
        "let a = [1, 2, 3]\ntake(a[five()])\ntake(a[2 + 3])",
    ])
    func `an index in range, or one not written as a literal, compiles`(body: String) {
        #expect(errorLines(body) == [])
    }
}
