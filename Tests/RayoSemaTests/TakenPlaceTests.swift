import Testing
import RayoDiagnostics

/// The declarations the tests' bodies use: a struct with a nested struct and an array in it.
private let declarations = """
    struct Enemy(var stats: Stats, var slots: [2 of Int])
    struct Stats(var hp: Int)
    func makeEnemy() -> Enemy { Enemy(stats: Stats(hp: 1), slots: [1, 2]) }
    """

/// The locals the tests' bodies start from.
private let locals = """
    var a = 1
        var b = 2
        var e = makeEnemy()
        var g: [2 of [2 of Int]] = [[1, 2], [3, 4]]
        var i: UInt = 1
        var c = true
    """

/// The errors that `statement`, after `locals` in `main`'s body, reports, each as its column, code and message. The
/// statement is the line after the locals, so the line number says nothing more.
private func messages(of statement: String) -> [String] {
    errorLines(inMain: "\(locals)\n    \(statement)", beside: declarations).map { line in
        String(line.drop { $0 != ":" }.dropFirst())
    }
}

/// The fix that every error for a place given to a position that can't borrow it ends with.
private let fix = "write 'copy' before it to take a copy, or 'consume' to move it"

struct TakenPlaceTests {
    // A `var` that borrowed its place could never change, so it takes a copy or the value itself, written out.
    @Test(arguments: [
        ("var x = a", "a"), ("var x = e.stats.hp", "e.stats.hp"), ("var x = e.slots[1]", "e.slots[1]"),
        ("var x = g[i][0]", "g[i][0]"), ("var x = g[i + 1][0]", "g[…][0]"),
    ])
    func `a 'var' given a place names the place, and says to write 'copy' or 'consume'`(
        statement: String, place: String,
    ) {
        #expect(messages(of: statement) == ["13: error[E0277]: a 'var' can't borrow '\(place)'; \(fix)"])
    }

    // An assignment that borrowed its place would leave its target naming a value it doesn't own.
    @Test(arguments: [("b = a", 9, "a"), ("e.stats.hp = g[0][1]", 18, "g[0][1]")])
    func `an assignment of a place names the place, and says to write 'copy' or 'consume'`(
        statement: String, column: Int, place: String,
    ) {
        #expect(messages(of: statement) == ["\(column): error[E0278]: an assignment can't borrow '\(place)'; \(fix)"])
    }

    // An `if` hands its position to the branch that runs, so each branch that ends in a place is reported there.
    @Test func `each branch of an 'if' that gives a 'var' or an assignment a place is reported`() {
        #expect(messages(of: "var x = if c { a } else if !c { b } else { copy a }").map { $0.prefix(16) } == [
            "20: error[E0277]", "37: error[E0277]",
        ])
        #expect(messages(of: "b = if c { 1 } else { a }").map { $0.prefix(16) } == ["27: error[E0278]"])
    }

    // A value that no place holds is owned by what receives it, and so is a place in a temporary, which dies with its
    // statement. A compound assignment reads its value, as its operator's operand.
    @Test(arguments: [
        "var x = copy a", "var x = consume a", "var x = a + 1", "var x = makeEnemy().stats.hp", "var x = e.slots.count",
        "var x = if c { copy a } else { 1 }", "b = copy a", "b = consume a", "b = makeEnemy().stats.hp", "b += a",
        "let x = a\n    print(x)", "e.stats = consume e.stats",
    ])
    func `a value, a copy, a consume or a place in a temporary needs nothing written`(statement: String) {
        #expect(messages(of: statement) == [])
    }
}
