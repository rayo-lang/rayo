import Testing

/// A struct with a field called `count`, one that holds an array, functions that borrow a UInt and an Int, and one
/// that makes an array, which the bodies below use.
private let declarations = """
    struct Counter(var count: UInt)
    struct Enemy(var slots: [2 of Int])
    func take(_ n: UInt) {}
    func use(_ n: Int) {}
    func made() -> [2 of Int] { [1, 2] }
    """

struct ArrayCountTests {
    @Test func `an array's count uses the array, which must still hold its value`() {
        let body = "let a = [1, 2]\nlet b = a\ntake(a.count)\ntake(b.count)"
        #expect(errorLines(inMain: body, beside: declarations) == ["4:6: error[E0302]: 'a' was moved"])
    }
}
