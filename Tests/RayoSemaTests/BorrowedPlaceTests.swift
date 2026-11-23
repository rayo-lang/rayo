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
private let declarationFix = "write 'copy' or 'consume' before it, or '&' and declare 'ref let'"

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
    func `a 'let' or 'var' given a place names the place, and says to write 'copy', 'consume' or '&'`(
        statement: String, keyword: String, place: String,
    ) {
        #expect(messages(of: statement) == [
            "13: error[E0277]: a '\(keyword)' can't borrow '\(place)'; \(declarationFix)",
        ])
    }

    // A `let` or `var` that holds a reference would hold it as a value, which rayoc doesn't build.
    @Test(arguments: [
        ("let x = &a", "let", [13]), ("var x = &e.stats", "var", [13]), ("let x: Int = &a", "let", [18]),
        ("var x = if c { &a } else { &b }", "var", [20, 32]),
    ])
    func `a 'let' or 'var' given '&' of a place is reported as unsupported`(
        statement: String, keyword: String, columns: [Int],
    ) {
        #expect(messages(of: statement) == columns.map {
            "\($0): error[E0288]: a '\(keyword)' holding a reference isn't supported; declare 'ref let', or remove "
                + "the '&'"
        })
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
    // statement. A compound assignment reads its value, as its operator's operand.
    @Test(arguments: [
        "var x = copy a", "let x = consume a", "var x = a + 1", "let x = makeEnemy().stats.hp", "var x = e.slots.count",
        "var x = if c { copy a } else { 1 }", "b = copy a", "b = consume a", "b = makeEnemy().stats.hp", "b += a",
        "e.stats = consume e.stats",
    ])
    func `a value, a copy, a consume or a place in a temporary needs nothing written`(statement: String) {
        #expect(messages(of: statement) == [])
    }

    // A `ref let` takes a reference to the place it refers to, on each branch of an `if`.
    @Test(arguments: [
        "ref let x = &a", "ref let x = &e.stats", "ref let x = &g[i][0]", "ref let x = &e.slots[1]",
        "ref let x: Int = &a", "ref let x = if c { &g[0] } else { &g[1] }",
        "ref let x = if c { &e.stats.hp } else { &b }\n    print(x)",
    ])
    func `a 'ref let' takes '&' of a local, or of a field or an element of one`(statement: String) {
        #expect(messages(of: statement) == [])
    }

    // A place written bare is a value the `ref let` would copy or move, so the error names the reference to write.
    // The `ref let` still refers to the place, so the error leaves the body's meaning whole.
    @Test(arguments: [
        ("ref let x = a", 17, "a"), ("ref let x = e.stats", 17, "e.stats"), ("ref let x = g[i]", 17, "g[i]"),
        ("ref let x: Int = e.stats.hp", 22, "e.stats.hp"), ("ref let x = if c { &g[0] } else { g[1] }", 39, "g[1]"),
    ])
    func `a 'ref let' given a place without '&' names the place with '&'`(
        statement: String, column: Int, place: String,
    ) {
        #expect(messages(of: statement) == [
            "\(column): error[E0287]: a 'ref let' takes a reference; write '&\(place)'",
        ])
    }

    // A `mutable &` lends its place for change, which only a `ref var` takes, and rayoc builds no `ref var`.
    @Test(arguments: [("ref let x = mutable &a", 17), ("ref let x = if c { &a } else { mutable &b }", 36)])
    func `a 'ref let' given 'mutable &' reports the 'mutable &' as unsupported`(statement: String, column: Int) {
        #expect(messages(of: statement) == ["\(column): error[E0289]: 'mutable &' isn't supported"])
    }

    // Each branch of an `if` stands in the `ref let`'s position, so branches of two types are reported as an `if`'s.
    @Test func `a 'ref let' of an 'if' whose branches refer to places of two types reports the branches' types`() {
        #expect(messages(of: "ref let x = if c { &a } else { &c }") == [
            "36: error[E0254]: the 'if' gives Int in one branch and Bool in another",
        ])
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

    // `&` of an array's count, or of a call's result or a part of it, lends a temporary that holds the value, which
    // rayoc lends nowhere.
    @Test(arguments: [
        ("ref let x = &e.slots.count", 17), ("ref let x = if c { &i } else { &e.slots.count }", 36),
        ("ref let x = &makeEnemy()", 17), ("ref let x = &makeEnemy().stats.hp", 17),
    ])
    func `a 'ref let' given '&' of a value that no local holds reports the lending as unsupported`(
        statement: String, column: Int,
    ) {
        #expect(messages(of: statement) == [
            "\(column): error[E0286]: lending a value that no local holds isn't supported; put it in a 'let' and "
                + "lend that",
        ])
    }

    // A `ref let` refers to a place, so a value that no place holds, a place in a temporary among them, gives it
    // nothing to refer to. Each branch of an `if` stands in the `ref let`'s position, so each that gives a value is
    // reported, even beside one that gives a place.
    @Test(arguments: [
        ("ref let x = 1", [17]), ("ref let x = copy a", [17]), ("ref let x = makeEnemy().stats", [17]),
        ("ref let x = a + b", [17]), ("ref let x = if c { &e.stats.hp } else { 1 }", [45]),
        ("ref let x = if c { copy a } else { 1 }", [24, 40]),
    ])
    func `a 'ref let' given a value says to declare 'let' or 'var'`(statement: String, columns: [Int]) {
        #expect(messages(of: statement) == columns.map {
            "\($0): error[E0280]: a 'ref let' refers to a place, not a value; declare 'let' or 'var' to own the value"
        })
    }

    // A local that a branch declares ends with the branch, while a `ref let` outside it lives on, so the `ref let`
    // can't refer to it, whether the branch ends in the local or in a part of it.
    @Test(arguments: [
        ("ref let x = if c {\n        let t = a + 1\n        &t\n    } else { &b }\n    print(x)", "x", "t"),
        (
            "ref let s = if c {\n        let f = makeEnemy()\n        &f.stats\n    } else { &e.stats }\n"
                + "    print(s.hp)",
            "s", "f.stats",
        ),
    ])
    func `a 'ref let' of a place in a local that ends with its branch says to declare 'let'`(
        statement: String, binding: String, place: String,
    ) {
        #expect(messages(of: statement) == [
            "10: error[E0279]: '\(place)' ends with its block before '\(binding)' does; declare 'let' and write "
                + "'copy' or 'consume' before it",
        ])
    }

    @Test(arguments: ["ref var x = a", "ref var x = &a", "ref var x = mutable &a"])
    func `a 'ref var' is reported as unsupported, whatever its place is written as`(statement: String) {
        #expect(messages(of: "\(statement)\n    print(x)") == ["13: error[E0281]: 'ref var' isn't supported"])
    }

    @Test func `a 'var' of '_' is reported for its name alone, whatever its value`() {
        #expect(messages(of: "var _ = a").map { $0.prefix(16) } == ["9: error[E0218]:"])
    }
}
