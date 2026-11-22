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
    // A `ref let` refers to its place, read-only, so the place keeps its value and can be used beside the `ref let`.
    @Test(arguments: [
        "    var a = 1\n    ref let b = a\n    print(a + b)",
        "\(enemy)\n    ref let s = e.stats\n    print(e.stats.hp + s.hp + e.slots[0])",
        "\(enemy)\n    ref let x = e.slots[1]\n    ref let y = e.slots[1]\n    print(x + y + e.slots[1])",
        "\(enemy)\n    ref let s = e.stats\n    ref let hp = s.hp\n    print(hp + s.hp + e.stats.hp)",
        "\(enemy)\n    let c = true\n    ref let v = if c { e.slots[0] } else { e.slots[1] }\n"
            + "    print(v + e.slots[0])",
    ])
    func `a 'ref let' borrows its place, and the place stays usable beside it`(body: String) {
        #expect(reports(ofMain: body) == [])
    }

    @Test func `a 'ref let' of a borrowed parameter or a part of one borrows it`() {
        let source = """
            func main() {
                print(total(Enemy(stats: Stats(hp: 1), slots: [2, 3]), 4))
            }
            func total(_ e: &Enemy, _ n: Int) -> Int {
                ref let s = e.stats
                ref let first = e.slots[0]
                ref let m = n
                return s.hp + first + m + n
            }
            \(declarations)
            """
        #expect(diagnostics(source).map(\.description) == [])
    }

    // The place can't change or move while the `ref let` is used later, since the `ref let` sees the place itself.
    @Test(arguments: [
        ("    var a = 1\n    ref let b = a\n    a = 5\n    print(b)", [
            "4:5: error[E0313]: 'a' can't change while 'a' is borrowed", "3:17: note: borrowed here",
        ]),
        ("\(enemy)\n    ref let s = e.stats\n    e.stats.hp += 1\n    print(s.hp)", [
            "4:5: error[E0313]: 'e.stats.hp' can't change while 'e.stats' is borrowed", "3:17: note: borrowed here",
        ]),
        ("\(enemy)\n    ref let hp = e.stats.hp\n    e = Enemy(stats: Stats(hp: 0), slots: [0, 0])\n"
            + "    print(hp + e.slots[0])", [
            "4:5: error[E0313]: 'e' can't change while 'e.stats.hp' is borrowed", "3:18: note: borrowed here",
        ]),
        ("\(enemy)\n    ref let s = e.stats\n    let t = consume e\n    print(s.hp + t.stats.hp)", [
            "4:13: error[E0314]: 'e' can't be moved while 'e.stats' is borrowed", "3:17: note: borrowed here",
        ]),
        ("    var a = 1\n    ref let b = a\n    ref let d = b\n    a += 1\n    print(d + a)", [
            "5:5: error[E0313]: 'a' can't change while 'a' is borrowed", "3:17: note: borrowed here",
        ]),
    ])
    func `a change or a move of the place while the 'ref let' is used later is reported where it happens`(
        body: String, expected: [String],
    ) {
        #expect(reports(ofMain: body) == expected)
    }

    // A borrow lasts until the `ref let` is last used, not to the end of its block.
    @Test(arguments: [
        "    var a = 1\n    ref let b = a\n    print(b)\n    a = 5\n    print(a)",
        "    var a = 1\n    var i = 0\n    while i < 2 {\n        ref let b = a\n        print(b)\n        a += 1\n"
            + "        i += 1\n    }\n    print(a)",
        "\(enemy)\n    ref let s = e.stats\n    print(s.hp)\n    let t = consume e\n    print(t.stats.hp)",
    ])
    func `the place may change once the 'ref let' is last used`(body: String) {
        #expect(reports(ofMain: body) == [])
    }

    // An `if` hands its position to the branch that runs, so the `ref let` borrows whichever place that branch ends
    // in.
    @Test func `a 'ref let' of an 'if' borrows the place of each branch, on the paths through it`() {
        let body = "    let c = true\n    var a = 1\n    var b = 2\n    ref let v = if c { a } else { b }\n    b = 3\n"
            + "    print(v + a + b)"
        #expect(reports(ofMain: body) == [
            "6:5: error[E0313]: 'b' can't change while 'b' is borrowed", "5:35: note: borrowed here",
        ])
    }

    // A branch that borrows through another `ref let` keeps that one's borrow too, while the branch that gives a value
    // borrows nothing; where the branches join, each holds the borrows the other still needs.
    @Test(arguments: [
        ("\(enemy)\n    let c = false\n    ref let st = e.stats\n    ref let deep = if c { st.hp } else { 5 }\n"
            + "    print(deep)\n    e.stats.hp = 2\n    print(e.stats.hp)", []),
        ("\(enemy)\n    let c = false\n    ref let st = e.stats\n"
            + "    ref let deep = if c { st.hp } else { e.slots[1] }\n    print(deep)\n    e.stats.hp = 2\n"
            + "    print(e.stats.hp)", []),
        ("\(enemy)\n    let c = false\n    ref let st = e.stats\n    ref let deep = if c { st.hp } else { 5 }\n"
            + "    e.stats.hp = 2\n    print(deep)", [
                "6:5: error[E0313]: 'e.stats.hp' can't change while 'e.stats' is borrowed",
                "4:18: note: borrowed here",
            ]),
    ])
    func `a 'ref let' of an 'if' with one branch borrowing through another 'ref let' keeps that borrow`(
        body: String, expected: [String],
    ) {
        #expect(reports(ofMain: body) == expected)
    }

    // Each branch borrows the place on its own path, and a move after the `if` that conflicts with both is one mistake.
    @Test func `a use that conflicts with the borrow of each branch is reported once, with a note for each borrow`() {
        let body = "\(enemy)\n    let c = true\n    ref let v = if c { e.stats } else { e.stats }\n"
            + "    let w = consume e\n    print(v.hp + w.stats.hp)"
        #expect(reports(ofMain: body) == [
            "5:13: error[E0314]: 'e' can't be moved while 'e.stats' is borrowed", "4:24: note: borrowed here",
            "4:41: note: borrowed here",
        ])
    }

    // A `ref let` gives up no value of its own, since its value is the place's.
    @Test(arguments: [
        ("    var a = 1\n    ref let b = a\n    let d = consume b\n    print(d + a)",
         "4:13: error[E0316]: can't move 'b', which refers to a place; write 'copy' before it to take a copy"),
        ("\(enemy)\n    ref let s = e.stats\n    let hp = consume s.hp\n    print(hp + e.slots[0])",
         "4:14: error[E0317]: can't move 's.hp' out of 's', which refers to a place; write 'copy' before it to "
            + "take a copy"),
    ])
    func `a move out of a 'ref let' is reported, with the copy to write`(body: String, message: String) {
        #expect(reports(ofMain: body) == [message])
    }
}
