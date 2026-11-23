import Testing

/// A struct that holds arrays, in a `var` field and in a `let` one, and functions that make an array and borrow an
/// Int, which the bodies below use.
private let declarations = """
    struct Enemy(var slots: [2 of Int], let fixed: [2 of Int])
    func made() -> [2 of Int] { [1, 2] }
    func take(_ n: Int) {}
    """

/// The errors that `body`, as the body of a function that borrows the array `p`, reports, each as its position, code
/// and message. The body starts on line 3.
private func errorLines(_ body: String) -> [String] {
    diagnostics("func main() {}\nfunc f(_ p: &[2 of Int]) {\n\(body)\n}\n\(declarations)").map(\.description)
}

struct ElementAssignmentTests {
    @Test(arguments: [
        "var a = [1, 2]\na[0] = 3\na[1] += a[0]\ntake(a[1])",
        "var a = [1, 2]\nlet i: UInt = 1\na[i] = 3\na[i - 1] -= 1\ntake(a[0] + a[i])",
        "var e = Enemy(slots: [1, 2], fixed: [3, 4])\ne.slots[1] = 5\ne.slots[0] *= 2\ntake(e.slots[0] + e.slots[1])",
        "var grid = [[1, 2], [3, 4]]\ngrid[1][0] = 5\ngrid[0] = [6, 7]\ntake(grid[0][1] + grid[1][0] + grid[1][1])",
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
        ("made()[0] = 1", "3:1: error[E0291]: 'made()' is a temporary; keep it in a 'var'"),
    ])
    func `an element is assigned only where a field would be`(body: String, expected: String) {
        #expect(errorLines(body) == [expected])
    }
}
