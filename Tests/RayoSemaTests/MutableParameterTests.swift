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
    errorLines(inMain: "\(locals)\n    \(statement)", beside: declarations).map { line in
        String(line.drop { $0 != ":" }.dropFirst())
    }
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
        "func f(_ n: Int) { bump(mutable n) }",
        "func f(_ e: mutable &Enemy) {\n    heal(mutable e)\n    bump(mutable e.stats.hp)\n}",
    ])
    func `a parameter that owns its argument, or borrows it for change, is lent with 'mutable'`(declaration: String) {
        #expect(declarationMessages(of: declaration) == [])
    }

    // A `mutable &T` parameter is lent shared, or copied, as any place is.
    @Test func `a 'mutable &T' parameter is passed on bare or with '&' to a '&T' parameter, to 'print' or copied`() {
        let body = "    show(e)\n    show(&e)\n    print(e.stats.hp)\n    keep(e.stats.hp)\n    let hp = e.slots[0]"
        #expect(declarationMessages(of: "func f(_ e: mutable &Enemy) {\n\(body)\n    print(hp)\n}") == [])
    }

    @Test(arguments: [
        ("bump(mutable fixed)", 10), ("heal(mutable fixedEnemy)", 10), ("bump(mutable fixedEnemy.stats.hp)", 10),
        ("bump(mutable e.id)", 10), ("bump(mutable seen.stats.hp)", 10), ("bumpCount(mutable e.slots.count)", 15),
        ("heal(mutable makeEnemy())", 10), ("bump(mutable makeEnemy().stats.hp)", 10),
    ])
    func `'mutable' of a place that isn't changeable is reported as unsupported`(statement: String, column: Int) {
        #expect(messages(of: statement) == ["\(column): error[E0289]: 'mutable' isn't supported"])
    }

    @Test func `'mutable' of a '&T' parameter is reported as unsupported`() {
        #expect(declarationMessages(of: "func f(_ e: &Enemy) { heal(mutable e) }") == [
            "14:28: error[E0289]: 'mutable' isn't supported",
        ])
    }

    @Test(arguments: [
        ("heal(e)", 10, "heal", "mutable &Enemy", "e"), ("bump(e.stats.hp)", 10, "bump", "mutable &Int", "e.stats.hp"),
        ("heal(w.enemies[i])", 10, "heal", "mutable &Enemy", "w.enemies[i]"),
        ("bump(&a)", 10, "bump", "mutable &Int", "a"), ("bump(fixed)", 10, "bump", "mutable &Int", "fixed"),
        ("bump(if c { a } else { mutable a })", 17, "bump", "mutable &Int", "a"),
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
    ])
    func `a value given to a 'mutable &T' parameter is a temporary whose change does nothing`(
        statement: String, column: Int, temporary: String,
    ) {
        #expect(messages(of: statement) == [
            "\(column): error[E0291]: changing '\(temporary)' does nothing, since it's dropped right after; "
                + "store it in a 'var' first",
        ])
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

    // An `if` gives a value, and a call lends a parameter that borrows for change a place alone.
    @Test func `an 'if' given to a 'mutable &T' parameter reports the 'mutable' of each branch as unsupported`() {
        #expect(messages(of: "bump(if c { mutable a } else { mutable e.stats.hp })") == [
            "17: error[E0289]: 'mutable' isn't supported", "36: error[E0289]: 'mutable' isn't supported",
        ])
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
        let reported = errorLines(inMain: "    var a = 1\n    \(call)", beside: overloads).map { line in
            String(line.drop { $0 != ":" }.dropFirst())
        }
        #expect(reported == expected)
    }
}
