import Testing
import RayoDiagnostics

/// A struct with a field called `count`, one that holds an array, and functions that borrow a UInt and an Int, which
/// the bodies below use.
private let declarations = """
    struct Counter(var count: UInt)
    struct Enemy(var slots: [2 of Int])
    func take(_ n: UInt) {}
    func use(_ n: Int) {}
    """

/// The errors that `body`, as `main`'s body beside `declarations`, reports, each as its position, code and message.
private func errorLines(_ body: String) -> [String] {
    diagnostics("func main() {\n\(body)\n}\n\(declarations)").map(\.description)
}

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
        #expect(errorLines(body) == [])
    }

    @Test(arguments: [
        ("var a = [1, 2]\na.count = 3\nuse(a[0])", countAssignment(at: "3:3")),
        ("var e = Enemy(slots: [1, 2])\ne.slots.count += 1\nuse(e.slots[0])", countAssignment(at: "3:9")),
    ])
    func `an array's count can't be assigned`(body: String, expected: String) {
        #expect(errorLines(body) == [expected])
    }

    @Test(arguments: [
        ("let a = [1, 2]\ntake(a.size)", "3:8: error[E0270]: [2 of Int] has no member 'size'"),
        ("let a = [1, 2]\ntake(a.count.size)", "3:14: error[E0244]: UInt has no field 'size'"),
    ])
    func `an array has no member but its count, and a count has none`(body: String, expected: String) {
        #expect(errorLines(body) == [expected])
    }

    @Test func `an array's count uses the array, which must still hold its value`() {
        let body = "let a = [1, 2]\nlet b = a\ntake(a.count)\ntake(b.count)"
        #expect(errorLines(body) == ["4:6: error[E0302]: 'a' was moved"])
    }
}
