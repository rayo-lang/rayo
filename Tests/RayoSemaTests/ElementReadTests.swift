import Testing

/// A struct, another that holds an array, and a function that borrows an Int, which the bodies below use.
private let declarations = """
    struct Stats(var hp: Int)
    struct Enemy(var slots: [2 of Int])
    func take(_ n: Int) {}
    """

struct ElementReadTests {
    @Test(arguments: [
        ("let a = [1, 2]\nlet i = 1\ntake(a[i])", "4:8: error[E0272]: an index needs a UInt, found Int"),
        ("let n = 1\ntake(n[0])", "3:6: error[E0271]: only an array can be indexed, found Int"),
        ("let s = Stats(hp: 1)\ntake(s[0].hp)", "3:6: error[E0271]: only an array can be indexed, found Stats"),
    ])
    func `an index is a UInt, and only an array is indexed`(body: String, expected: String) {
        #expect(errorLines(inMain: body, beside: declarations) == [expected])
    }
}
