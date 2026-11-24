import Testing
import RayoDiagnostics

/// The declarations the tests' bodies use: structs with `var` and `let` fields and an array in one, and functions
/// that borrow their arguments for change, borrow them, or own them.
private let declarations = """
    struct Enemy(var stats: Stats, var slots: [2 of Int], let id: Int)
    struct Stats(var hp: Int)
    struct Wave(var enemies: [2 of Enemy])
    func makeEnemy() -> Enemy { Enemy(stats: Stats(hp: 1), slots: [1, 2], id: 0) }
    func heal(_ e: mutable &Enemy) { e.stats.hp = 100 }
    func bump(_ n: mutable &Int) { n += 1 }
    func bumpCount(_ n: mutable &UInt) { n += 1 }
    func fill(_ s: mutable &[2 of Int]) { s[0] = 1 }
    func show(_ e: &Enemy) {}
    func keep(_ n: Int) { print(n) }
    """

/// The locals the tests' bodies start from.
private let locals = """
    var a = 1
        var e = makeEnemy()
        var w = Wave(enemies: [makeEnemy(), makeEnemy()])
        var i: UInt = 1
        var c = true
        let fixed = 1
        let fixedEnemy = makeEnemy()
        ref let seen = &e
    """

/// The errors that `statement`, after `locals` in `main`'s body, reports, each as its column, code and message. The
/// statement is the line after the locals, so the line number says nothing more.
private func messages(of statement: String) -> [String] {
    lineMessages(inMain: "\(locals)\n    \(statement)", beside: declarations)
}

/// The errors that `body`, as `main`'s body beside `declarations`, reports, each as its column, code and message,
/// for a body whose errors are all on one line.
private func lineMessages(inMain body: String, beside declarations: String) -> [String] {
    errorLines(inMain: body, beside: declarations).map { line in String(line.drop { $0 != ":" }.dropFirst()) }
}

/// The errors that `declaration`, beside `declarations` and an empty `main`, reports, each as its position, code and
/// message.
private func declarationMessages(of declaration: String) -> [String] {
    errorLines(inMain: "", beside: "\(declarations)\n\(declaration)")
}

struct MutableParameterTests {
    @Test func `a parameter may borrow an Int, a UInt, a Bool, a struct or an array for change`() {
        let declaration = "func f(_ n: mutable &Int, _ u: mutable &UInt, _ b: mutable &Bool, _ e: mutable &Enemy, "
            + "_ s: mutable &[2 of Int]) {}"
        #expect(declarationMessages(of: declaration) == [])
    }

    // The parameter names its caller's place, which the body reads and changes as it would a `var`.
    @Test func `a body reads and changes a 'mutable &T' parameter, its 'var' fields and elements, and replaces it`() {
        let body = "    print(e.stats.hp)\n    e.stats.hp += 1\n    e.slots[0] = e.slots[1]\n    e = makeEnemy()"
        #expect(declarationMessages(of: "func f(_ e: mutable &Enemy) {\n\(body)\n}") == [])
    }

    @Test func `a 'let' field of a 'mutable &T' parameter can't change`() {
        #expect(declarationMessages(of: "func f(_ e: mutable &Enemy) { e.id = 1 }") == [
            "14:33: error[E0252]: 'id' is a 'let' field, so it can't change",
        ])
    }

    @Test(arguments: [
        "bump(mutable a)", "heal(mutable e)", "bump(mutable e.stats.hp)", "fill(mutable e.slots)",
        "bump(mutable e.slots[i])", "heal(mutable w.enemies[i])", "bump(mutable w.enemies[i].stats.hp)",
    ])
    func `a call lends a 'var', or a 'var' field or an element of one at any depth, with 'mutable'`(
        statement: String,
    ) {
        #expect(messages(of: statement) == [])
    }

    @Test(arguments: [
        ("n: Int", "bump(mutable n)"),
        ("e: Enemy", "heal(mutable e)\n    bump(mutable e.stats.hp)\n    bump(mutable e.slots[0])"),
        ("e: mutable &Enemy", "heal(mutable e)\n    bump(mutable e.stats.hp)\n    bump(mutable e.slots[0])"),
    ])
    func `a parameter that owns its argument, or borrows it for change, is lent with 'mutable', and so are its parts`(
        parameter: String, body: String,
    ) {
        #expect(declarationMessages(of: "func f(_ \(parameter)) {\n    \(body)\n}") == [])
    }

    // A `mutable &T` parameter is lent shared, or copied, as any place is.
    @Test func `a 'mutable &T' parameter is passed on bare or with '&' to a '&T' parameter, to 'print' or copied`() {
        let body = "    show(e)\n    show(&e)\n    print(e.stats.hp)\n    keep(e.stats.hp)\n    let hp = e.slots[0]"
        #expect(declarationMessages(of: "func f(_ e: mutable &Enemy) {\n\(body)\n    print(hp)\n}") == [])
    }

    @Test(arguments: [
        ("bump(mutable fixed)", "fixed"), ("heal(mutable fixedEnemy)", "fixedEnemy"),
        ("bump(mutable fixedEnemy.stats.hp)", "fixedEnemy"), ("fill(mutable fixedEnemy.slots)", "fixedEnemy"),
        ("bump(mutable fixedEnemy.slots[i])", "fixedEnemy"),
    ])
    func `'mutable' of a 'let', or of a part of one, names it and says to declare it 'var'`(
        statement: String, name: String,
    ) {
        #expect(messages(of: statement) == [
            "18: error[E0295]: '\(name)' is a 'let', so it can't change; declare it 'var'",
        ])
    }

    @Test func `'mutable' of a 'ref let' names it`() {
        #expect(messages(of: "heal(mutable seen)") == ["18: error[E0296]: 'seen' is a 'ref let', so it can't change"])
    }

    // A part of a `ref let` is reported as an assignment into it is.
    @Test(arguments: ["bump(mutable seen.stats.hp)", "fill(mutable seen.slots)", "bump(mutable seen.slots[i])"])
    func `'mutable' of a part of a 'ref let' names it`(statement: String) {
        #expect(messages(of: statement) == [
            "18: error[E0251]: 'seen' is a 'let', so its fields and elements can't change",
        ])
    }

    // A `let` field never changes, whatever holds it, so it is reported ahead of a root that can't change either.
    @Test(arguments: [("bump(mutable e.id)", 20), ("bump(mutable fixedEnemy.id)", 29), ("bump(mutable seen.id)", 23)])
    func `'mutable' of a 'let' field names the field`(statement: String, column: Int) {
        #expect(messages(of: statement) == ["\(column): error[E0252]: 'id' is a 'let' field, so it can't change"])
    }

    @Test func `'mutable' of a 'let' field of a '&T' parameter names the field`() {
        #expect(declarationMessages(of: "func f(_ e: &Enemy) { bump(mutable e.id) }") == [
            "14:38: error[E0252]: 'id' is a 'let' field, so it can't change",
        ])
    }

    // An array's count never changes, whatever holds the array, so it is reported ahead of a root that can't change
    // either.
    @Test(arguments: [("bumpCount(mutable e.slots.count)", 31), ("bumpCount(mutable fixedEnemy.slots.count)", 40)])
    func `'mutable' of an array's count says its type fixes it`(statement: String, column: Int) {
        #expect(messages(of: statement) == [
            "\(column): error[E0273]: an array's 'count' is fixed by its type, so it can't change",
        ])
    }

    @Test(arguments: ["heal(mutable e)", "bump(mutable e.stats.hp)", "bump(mutable e.slots[0])"])
    func `'mutable' of a '&T' parameter, or of a part of one, says to take it as 'mutable &T'`(statement: String) {
        #expect(declarationMessages(of: "func f(_ e: &Enemy) { \(statement) }") == [
            "14:36: error[E0230]: 'e' is a '&Enemy' parameter, so it can't change; take it as 'mutable &Enemy'",
        ])
    }

    @Test(arguments: [
        ("heal(e)", 10, "heal", "mutable &Enemy", "e"), ("bump(e.stats.hp)", 10, "bump", "mutable &Int", "e.stats.hp"),
        ("heal(w.enemies[i])", 10, "heal", "mutable &Enemy", "w.enemies[i]"),
        ("bump(&a)", 10, "bump", "mutable &Int", "a"), ("bump(fixed)", 10, "bump", "mutable &Int", "fixed"),
    ])
    func `a place given to a 'mutable &T' parameter without 'mutable' names the 'mutable' to write`(
        statement: String, column: Int, callee: String, type: String, place: String,
    ) {
        #expect(messages(of: statement) == [
            "\(column): error[E0293]: '\(callee)' takes '\(type)'; write 'mutable \(place)'",
        ])
    }

    @Test(arguments: [
        ("bump(1)", 10, "1"), ("bump(copy a)", 10, "copy a"), ("bump(a + 1)", 10, "a + 1"),
        ("heal(makeEnemy())", 10, "makeEnemy()"), ("bump(makeEnemy().stats.hp)", 10, "makeEnemy()"),
        ("bump(&makeEnemy().stats.hp)", 11, "makeEnemy()"),
        ("bump(if c { a } else { e.stats.hp })", 10, "if c { a } else { e.stats.hp }"),
    ])
    func `a value given to a 'mutable &T' parameter is a temporary whose change does nothing`(
        statement: String, column: Int, temporary: String,
    ) {
        #expect(messages(of: statement) == [changedTemporary(temporary, at: "\(column)")])
    }

    @Test(arguments: [
        ("show(mutable e)", 10, "show", "&Enemy"), ("keep(mutable a)", 10, "keep", "Int"),
        ("print(mutable a)", 11, "print", "&Int"), ("_ = Stats(hp: mutable a)", 19, "Stats", "Int"),
        ("let s: [2 of Int] = .init(repeating: mutable a)", 42, ".init", "Int"),
    ])
    func `'mutable' given to a parameter that takes no mutable reference names its type`(
        statement: String, column: Int, callee: String, type: String,
    ) {
        #expect(messages(of: statement) == [
            "\(column): error[E0294]: '\(callee)' takes '\(type)', not a mutable reference; remove the 'mutable'",
        ])
    }

    @Test(arguments: [("bump(mutable c)", 10, "Int", "Bool"), ("heal(&a)", 10, "Enemy", "Int")])
    func `a place of another type than a 'mutable &T' parameter's is a type mismatch`(
        statement: String, column: Int, expected: String, found: String,
    ) {
        #expect(messages(of: statement) == ["\(column): error[E0213]: expected \(expected), found \(found)"])
    }

    // An `if` gives a value, and a call lends a parameter that borrows for change a place alone, so each branch of
    // the `if` takes no reference.
    @Test(arguments: [
        ("bump(if c { mutable a } else { mutable e.stats.hp })", [17, 36]),
        ("bump(if c { a } else { mutable a })", [28]),
    ])
    func `an 'if' given to a 'mutable &T' parameter reports the 'mutable' of each branch as unsupported`(
        statement: String, columns: [Int],
    ) {
        #expect(messages(of: statement) == columns.map { "\($0): error[E0289]: 'mutable' isn't supported" })
    }

    @Test func `functions whose parameters differ only in '&T' and 'mutable &T' are declared once each`() {
        #expect(declarationMessages(of: "func f(_ x: &Int) {}\nfunc f(_ x: mutable &Int) {}") == [])
    }

    // A call picks among overloads by how each argument is written, and a `mutable` picks the one that borrows for
    // change.
    @Test(arguments: [
        ("f(a)", []), ("f(&a)", []), ("f(mutable a)", []), ("g(mutable a)", []), ("g(a)", []),
        ("h(mutable a)", ["5: error[E0231]: no 'h' takes the arguments (mutable &Int)"]),
        ("h(&a)", ["5: error[E0231]: no 'h' takes the arguments (&Int)"]),
    ] as [(String, [String])])
    func `a 'mutable' argument reaches the overload that borrows for change, and any other argument another`(
        call: String, expected: [String],
    ) {
        let overloads = """
            func f(_ x: &Int) {}
            func f(_ x: mutable &Int) {}
            func g(_ x: Int) { print(x) }
            func g(_ x: mutable &Int) {}
            func h(_ x: &Bool) {}
            func h(_ x: mutable &Bool) {}
            """
        #expect(lineMessages(inMain: "    var a = 1\n    \(call)", beside: overloads) == expected)
    }
}
