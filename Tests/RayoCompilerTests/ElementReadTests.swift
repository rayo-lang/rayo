import Testing
import RayoDiagnostics

/// A struct, another that holds an array, and a function that borrows an Int, which the bodies below use.
private let declarations = """
    struct Stats(var hp: Int)
    struct Enemy(var slots: [2 of Int])
    func take(_ n: Int) {}
    """

/// The error at a move out of an element, at `position`.
private func elementMove(at position: String) -> String {
    "\(position): error[E0315]: an array's element can't be moved, nor any part of one; 'copy' makes an owned copy"
}

struct ElementReadTests {
    @Test(arguments: [
        "let a = [1, 2]\ntake(a[0])\ntake(a[1])\ntake(a[0] + a[1])",
        "let a = [1, 2]\nlet i: UInt = 1\ntake(a[i])\ntake(a[i - 1])\nif a[i] > 0 { take(1) }",
        "let a = [Stats(hp: 1)]\ntake(a[0].hp)\nlet hp = copy a[0].hp\ntake(hp)\nlet s = copy a[0]\ntake(s.hp)",
        "let grid = [[1, 2], [3, 4]]\ntake(grid[1][0])\nlet row = copy grid[1]\ntake(row[0])",
        "let a = [1, 2]\nlet b = a\ntake(b[0])",
    ])
    func `an element is borrowed where it is read, and copied with 'copy'`(body: String) {
        #expect(errorLines(inMain: body, beside: declarations) == [])
    }

    @Test(arguments: [
        ("let a = [1, 2]\nlet x = a[0]", elementMove(at: "3:9")),
        ("let a = [Stats(hp: 1)]\nlet i: UInt = 0\nlet x = a[i].hp", elementMove(at: "4:9")),
        ("let a = [[1, 2]]\n_ = a[0][1]", elementMove(at: "3:5")),
    ])
    func `an element, or a part of one, can't be moved out of its array`(body: String, expected: String) {
        #expect(errorLines(inMain: body, beside: declarations) == [expected])
    }

    @Test(arguments: [
        ("let a = [1, 2]\nlet i = 1\ntake(a[i])", "4:8: error[E0272]: an index needs a UInt, found Int"),
        ("let n = 1\ntake(n[0])", "3:6: error[E0271]: only an array can be indexed, found Int"),
        ("let s = Stats(hp: 1)\ntake(s[0].hp)", "3:6: error[E0271]: only an array can be indexed, found Stats"),
    ])
    func `an index is a UInt, and only an array is indexed`(body: String, expected: String) {
        #expect(errorLines(inMain: body, beside: declarations) == [expected])
    }

    @Test(arguments: [
        ("let a = [1, 2]\nlet b = a\ntake(a[0])", "4:6: error[E0302]: 'a' was moved"),
        ("var e = Enemy(slots: [1, 2])\nlet s = e.slots\ntake(e.slots[1])", "4:6: error[E0302]: 'e.slots' was moved"),
    ])
    func `an element of an array that was moved, or of one moved out of a struct, can't be read`(
        body: String, expected: String,
    ) {
        #expect(errorLines(inMain: body, beside: declarations) == [expected])
    }
}
