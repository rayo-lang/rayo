import Testing
import RayoDiagnostics

/// The declarations the tests' bodies use: a struct with a nested struct and an array in it.
private let declarations = """
    struct Enemy(var stats: Stats, var slots: [2 of Int])
    struct Stats(var hp: Int)
    """

/// The diagnostics that `body`, as `main`'s body, reports, each as its description followed by its notes. The body
/// starts on the source's second line.
private func reports(ofMain body: String) -> [String] {
    diagnostics("func main() {\n\(body)\n}\n\(declarations)").flatMap { [$0.description] + $0.notes }
}

/// `var e = …`, the line that gives a test's body an enemy to borrow.
private let enemy = "    var e = Enemy(stats: Stats(hp: 2), slots: [3, 4])"

struct BorrowTests {
    // A `let` given a place borrows it, read-only, so the place keeps its value and can be used beside the `let`.
    @Test(arguments: [
        "    var a = 1\n    let b = a\n    print(a + b)",
        "\(enemy)\n    let s = e.stats\n    print(e.stats.hp + s.hp + e.slots[0])",
        "\(enemy)\n    let x = e.slots[1]\n    let y = e.slots[1]\n    print(x + y + e.slots[1])",
        "\(enemy)\n    let s = e.stats\n    let hp = s.hp\n    print(hp + s.hp + e.stats.hp)",
        "\(enemy)\n    let c = true\n    let v = if c { e.slots[0] } else { e.slots[1] }\n    print(v + e.slots[0])",
    ])
    func `a 'let' of a place borrows it, and the place stays usable beside the 'let'`(body: String) {
        #expect(reports(ofMain: body) == [])
    }

    @Test func `a 'let' of a borrowed parameter or a part of one borrows it`() {
        let source = """
            func main() {
                print(total(Enemy(stats: Stats(hp: 1), slots: [2, 3]), 4))
            }
            func total(_ e: Enemy, _ n: Int) -> Int {
                let s = e.stats
                let first = e.slots[0]
                let m = n
                return s.hp + first + m + n
            }
            \(declarations)
            """
        #expect(diagnostics(source).map(\.description) == [])
    }

    // The place can't change or move while the `let` is used later, since the `let` sees the place itself.
    @Test(arguments: [
        ("    var a = 1\n    let b = a\n    a = 5\n    print(b)", [
            "4:5: error[E0313]: 'a' can't change while 'a' is borrowed", "3:13: note: borrowed here",
        ]),
        ("\(enemy)\n    let s = e.stats\n    e.stats.hp += 1\n    print(s.hp)", [
            "4:5: error[E0313]: 'e.stats.hp' can't change while 'e.stats' is borrowed", "3:13: note: borrowed here",
        ]),
        ("\(enemy)\n    let hp = e.stats.hp\n    e = Enemy(stats: Stats(hp: 0), slots: [0, 0])\n"
            + "    print(hp + e.slots[0])", [
            "4:5: error[E0313]: 'e' can't change while 'e.stats.hp' is borrowed", "3:14: note: borrowed here",
        ]),
        ("\(enemy)\n    let s = e.stats\n    let t = consume e\n    print(s.hp + t.stats.hp)", [
            "4:13: error[E0314]: 'e' can't be moved while 'e.stats' is borrowed", "3:13: note: borrowed here",
        ]),
        ("    var a = 1\n    let b = a\n    let d = b\n    a += 1\n    print(d + a)", [
            "5:5: error[E0313]: 'a' can't change while 'a' is borrowed", "3:13: note: borrowed here",
        ]),
    ])
    func `a change or a move of the place while the 'let' is used later is reported where it happens`(
        body: String, expected: [String],
    ) {
        #expect(reports(ofMain: body) == expected)
    }

    // A borrow lasts until the `let` is last used, not to the end of its block.
    @Test(arguments: [
        "    var a = 1\n    let b = a\n    print(b)\n    a = 5\n    print(a)",
        "    var a = 1\n    var i = 0\n    while i < 2 {\n        let b = a\n        print(b)\n        a += 1\n"
            + "        i += 1\n    }\n    print(a)",
        "\(enemy)\n    let s = e.stats\n    print(s.hp)\n    let t = consume e\n    print(t.stats.hp)",
    ])
    func `the place may change once the 'let' is last used`(body: String) {
        #expect(reports(ofMain: body) == [])
    }

    // An `if` hands its position to the branch that runs, so the `let` borrows whichever place that branch ends in.
    @Test func `a 'let' of an 'if' borrows the place of each branch, on the paths through it`() {
        let body = "    let c = true\n    var a = 1\n    var b = 2\n    let v = if c { a } else { b }\n    b = 3\n"
            + "    print(v + a + b)"
        #expect(reports(ofMain: body) == [
            "6:5: error[E0313]: 'b' can't change while 'b' is borrowed", "5:31: note: borrowed here",
        ])
    }

    // A borrowing `let` gives up no value of its own, since its value is the place's.
    @Test(arguments: [
        ("    var a = 1\n    let b = a\n    let d = consume b\n    print(d + a)",
         "4:13: error[E0316]: can't move 'b', which borrows its value; write 'copy' before it to take a copy"),
        ("\(enemy)\n    let s = e.stats\n    let hp = consume s.hp\n    print(hp + e.slots[0])",
         "4:14: error[E0317]: can't move 's.hp' out of 's', which borrows its value; write 'copy' before it to "
            + "take a copy"),
    ])
    func `a move out of a borrowing 'let' is reported, with the copy to write`(body: String, message: String) {
        #expect(reports(ofMain: body) == [message])
    }
}
