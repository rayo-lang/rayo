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

/// The fix that the error for a place given to a `let` or `var` ends with.
private let declarationFix = "write 'copy' or 'consume' before it, or declare 'ref let'"

/// The fix that the error for a place given to an assignment ends with.
private let ownedFix = "write 'copy' before it to take a copy, or 'consume' to move it"

struct BorrowedPlaceTests {
    // A `let` or `var` owns its value, and the place's value has an owner already, so the declaration writes how it
    // takes the value, or says that it refers to the place.
    @Test(arguments: [
        ("var x = e", "var", "e"), ("var x = e.stats", "var", "e.stats"),
        ("let x = e.slots", "let", "e.slots"), ("let x = g[i]", "let", "g[i]"),
        ("var x = g[i + 1]", "var", "g[…]"),
    ])
    func `a 'let' or 'var' given a place names the place, and says to write 'copy', 'consume' or 'ref let'`(
        statement: String, keyword: String, place: String,
    ) {
        #expect(messages(of: statement) == [
            "13: error[E0277]: a '\(keyword)' can't borrow '\(place)'; \(declarationFix)",
        ])
    }

    // An assignment that borrowed its place would leave its target naming a value it doesn't own.
    @Test(arguments: [("g[0] = g[1]", 12, "g[1]"), ("e.slots = g[0]", 15, "g[0]")])
    func `an assignment of a place names the place, and says to write 'copy' or 'consume'`(
        statement: String, column: Int, place: String,
    ) {
        #expect(messages(of: statement) == [
            "\(column): error[E0278]: an assignment can't borrow '\(place)'; \(ownedFix)",
        ])
    }

    // An `if` hands its position to the branch that runs, so each branch that ends in a place is reported there.
    @Test func `each branch of an 'if' that gives a 'let', a 'var' or an assignment a place is reported`() {
        #expect(messages(of: "var x = if c { g[0] } else if !c { g[1] } else { copy g[0] }").map { $0.prefix(16) } == [
            "20: error[E0277]", "40: error[E0277]",
        ])
        #expect(messages(of: "let x = if c { makeEnemy() } else { e }").map { $0.prefix(16) } == ["41: error[E0277]"])
        #expect(messages(of: "e = if c { makeEnemy() } else { e }").map { $0.prefix(16) } == ["37: error[E0278]"])
    }

    // A value that no place holds is owned by what receives it, and so is a place in a temporary, which dies with its
    // statement. A compound assignment reads its value, as its operator's operand, and a `ref let` refers to a place.
    @Test(arguments: [
        "var x = copy a", "let x = consume a", "var x = a + 1", "let x = makeEnemy().stats.hp", "var x = e.slots.count",
        "var x = if c { copy a } else { 1 }", "b = copy a", "b = consume a", "b = makeEnemy().stats.hp", "b += a",
        "ref let x = a\n    print(x)", "ref let x = if c { e.stats.hp } else { 1 }\n    print(x)",
        "e.stats = consume e.stats",
    ])
    func `a value, a copy, a consume, a place in a temporary or a 'ref let' needs nothing written`(statement: String) {
        #expect(messages(of: statement) == [])
    }

    // A `let`, a `var` or an assignment given a place of an implicitly copyable type takes a copy of its value.
    @Test(arguments: [
        "var x = a", "let x = e.stats.hp", "let x = g[i][0]", "var x = i", "let x = c", "b = a",
        "e.stats.hp = g[0][1]", "var x = if c { a } else { b }",
    ])
    func `a 'let', a 'var' or an assignment given an Int, a UInt or a Bool place needs nothing written`(
        statement: String,
    ) {
        #expect(messages(of: statement) == [])
    }

    // A `ref let` refers to a place, so a value that no place holds, a place in a temporary among them, gives it
    // nothing to refer to.
    @Test(arguments: ["ref let x = 1", "ref let x = copy a", "ref let x = makeEnemy().stats", "ref let x = a + b"])
    func `a 'ref let' given a value names the binding, and says to declare 'let' or 'var'`(statement: String) {
        #expect(messages(of: statement) == [
            "13: error[E0280]: 'x' has no place to refer to; declare it 'let' or 'var' to own its value",
        ])
    }

    // A local that a branch declares ends with the branch, while a `ref let` outside it lives on, so the `ref let`
    // can't refer to it, whether the branch ends in the local or in a part of it.
    @Test(arguments: [
        ("ref let x = if c {\n        let t = a + 1\n        t\n    } else { b }\n    print(x)", "x", "t"),
        (
            "ref let s = if c {\n        let f = makeEnemy()\n        f.stats\n    } else { e.stats }\n    print(s.hp)",
            "s", "f.stats",
        ),
    ])
    func `a 'ref let' of a place in a local that ends with its branch says to declare 'let'`(
        statement: String, binding: String, place: String,
    ) {
        #expect(messages(of: statement) == [
            "9: error[E0279]: '\(place)' ends with its block before '\(binding)' does; declare 'let' and write "
                + "'copy' or 'consume' before it",
        ])
    }

    @Test func `a 'ref var' is reported as unsupported`() {
        #expect(messages(of: "ref var x = a\n    print(x)") == ["13: error[E0281]: 'ref var' isn't supported"])
    }

    @Test func `a 'var' of '_' is reported for its name alone, whatever its value`() {
        #expect(messages(of: "var _ = a").map { $0.prefix(16) } == ["9: error[E0218]:"])
    }
}
