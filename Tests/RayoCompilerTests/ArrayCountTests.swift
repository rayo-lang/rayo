import Testing
import RayoDiagnostics

/// A struct with a field called `count`, one that holds an array, functions that borrow a UInt and an Int, and one
/// that makes an array, which the bodies below use.
private let declarations = """
    struct Counter(var count: UInt)
    struct Enemy(var slots: [2 of Int])
    func take(_ n: UInt) {}
    func use(_ n: Int) {}
    func made() -> [2 of Int] { [1, 2] }
    """

/// The error at an assignment to an array's count, whose name is at `position`.
private func countAssignment(at position: String) -> String {
    "\(position): error[E0273]: an array's 'count' is fixed by its type, so it can't change"
}

struct ArrayCountTests {
    @Test(arguments: [
        "let a = [1, 2]\ntake(a.count)",
        "let a = [1, 2]\nlet n = a.count\nlet m = copy a.count\ntake(n + m)",
        "let e = Enemy(slots: [1, 2])\nlet i: UInt = 1\ntake(e.slots.count)\nuse(e.slots[e.slots.count - i])",
        "var c = Counter(count: 1)\ntake(c.count)\nc.count = 2\ntake(c.count)",
    ])
    func `an array's count is a UInt, and a struct's field called count is still its field`(body: String) {
        #expect(errorLines(inMain: body, beside: declarations) == [])
    }

    @Test(arguments: [
        ("var a = [1, 2]\na.count = 3\nuse(a[0])", countAssignment(at: "3:3")),
        ("var e = Enemy(slots: [1, 2])\ne.slots.count += 1\nuse(e.slots[0])", countAssignment(at: "3:9")),
        ("let a = [1, 2]\na.count = 3\nuse(a[0])", countAssignment(at: "3:3")),
        ("var grid = [[1], [2]]\ngrid[0].count = 3\nuse(grid[0][0])", countAssignment(at: "3:9")),
        ("made().count = 3", countAssignment(at: "2:8")),
        ("var a = [1, 2]\na.count.size = 3\nuse(a[0])", countAssignment(at: "3:3")),
    ])
    func `an array's count can't be assigned, whatever holds the array`(body: String, expected: String) {
        #expect(errorLines(inMain: body, beside: declarations) == [expected])
    }

    @Test func `a borrowed parameter's count can't be assigned either`() {
        let source = "func main() {}\nfunc reset(_ a: [2 of Int]) {\n    a.count = 0\n}"
        #expect(diagnostics(source).map(\.description) == [countAssignment(at: "3:7")])
    }

    @Test(arguments: [
        ("let a = [1, 2]\ntake(a.size)", "3:8: error[E0270]: [2 of Int] has no member 'size'"),
        ("let a = [1, 2]\ntake(a.count.size)", "3:14: error[E0244]: UInt has no field 'size'"),
    ])
    func `an array has no member but its count, and a count has none`(body: String, expected: String) {
        #expect(errorLines(inMain: body, beside: declarations) == [expected])
    }

    @Test func `an array's count uses the array, which must still hold its value`() {
        let body = "let a = [1, 2]\nlet b = a\ntake(a.count)\ntake(b.count)"
        #expect(errorLines(inMain: body, beside: declarations) == ["4:6: error[E0302]: 'a' was moved"])
    }
}
