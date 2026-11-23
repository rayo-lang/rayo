import Testing
import RayoDiagnostics

/// The declarations the tests' bodies use: a struct with a nested struct and an array in it, and functions that
/// borrow or own their arguments.
private let declarations = """
    struct Enemy(var stats: Stats, var slots: [2 of Int])
    struct Stats(var hp: Int)
    func makeEnemy() -> Enemy { Enemy(stats: Stats(hp: 1), slots: [1, 2]) }
    func show(_ e: &Enemy) {}
    func showStats(_ s: &Stats) {}
    func read(_ n: &Int) {}
    func count(_ n: &UInt) {}
    func take(_ n: Int) {}
    func pair(_ n: &Int, with m: Int) {}
    func pass(_ e: &Enemy) { show(&e) }
    func passStats(_ e: &Enemy) { showStats(&e.stats) }
    """

/// The locals the tests' bodies start from.
private let locals = """
    var a = 1
        var e = makeEnemy()
        var g: [2 of Enemy] = [makeEnemy(), makeEnemy()]
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

/// The errors that `declaration`, beside an empty `main`, reports, each as its position, code and message.
private func declarationMessages(of declaration: String) -> [String] {
    diagnostics("func main() {}\nstruct Enemy(var hp: Int)\n\(declaration)").map(\.description)
}

struct ReferenceParameterTests {
    @Test(arguments: [
        "show(&e)", "showStats(&e.stats)", "read(&e.stats.hp)", "read(&e.slots[i])", "read(&a)", "show(&g[0])",
        "read(&g[i].stats.hp)", "pair(&a, with: a)", "show(if c { &e } else { &g[0] })", "pass(&e)",
    ])
    func `a '&T' parameter takes '&' of a local, a parameter, or a field or element of one`(statement: String) {
        #expect(messages(of: statement) == [])
    }

    @Test(arguments: [
        ("show(makeEnemy())", [10]), ("show(copy e)", [10]), ("read(1)", [10]), ("read(a + 1)", [10]),
        ("read(makeEnemy().stats.hp)", [10]), ("show(if c { makeEnemy() } else { copy e })", [17, 38]),
        ("show(if c { &e } else { makeEnemy() })", [29]), ("count(&e.slots.count)", [11]),
        ("count(if c { &i } else { &g[0].slots.count })", [30]), ("show(&makeEnemy())", [10]),
        ("read(&makeEnemy().stats.hp)", [10]),
    ])
    func `lending a value that no local or parameter holds to a '&T' parameter is reported as unsupported`(
        statement: String, columns: [Int],
    ) {
        #expect(messages(of: statement) == columns.map {
            "\($0): error[E0286]: lending a value that no local holds isn't supported; put it in a 'let' and lend that"
        })
    }

    @Test(arguments: [
        ("show(e)", 10, "an Enemy", "e"), ("read(a)", 10, "an Int", "a"),
        ("read(e.stats.hp)", 10, "an Int", "e.stats.hp"), ("show(g[i])", 10, "an Enemy", "g[i]"),
        ("showStats(e.stats)", 15, "a Stats", "e.stats"), ("pair(a, with: a)", 10, "an Int", "a"),
        ("show(if c { e } else { &g[0] })", 17, "an Enemy", "e"),
    ])
    func `a place given to a '&T' parameter without '&' names the place with '&'`(
        statement: String, column: Int, type: String, place: String,
    ) {
        let callee = statement.prefix { $0 != "(" }
        #expect(messages(of: statement) == [
            "\(column): error[E0283]: '\(callee)' takes a reference to \(type); write '&\(place)'",
        ])
    }

    @Test(arguments: [("read(&c)", "10: error[E0213]: expected Int, found Bool"),
                      ("showStats(&e)", "15: error[E0213]: expected Stats, found Enemy")])
    func `'&' of a place of another type than the parameter's is a type mismatch at the '&'`(
        statement: String, message: String,
    ) {
        #expect(messages(of: statement) == [message])
    }

    @Test(arguments: [
        ("take(&a)", 10, "take", "an Int"), ("print(&a)", 11, "print", "an Int"),
        ("_ = UInt(&a)", 14, "UInt", "an Int"), ("_ = Stats(hp: &a)", 19, "Stats", "an Int"),
        ("take(if c { &a } else { 1 })", 17, "take", "an Int"),
        ("let s: [2 of Int] = .init(repeating: &a)", 42, ".init", "an Int"),
    ])
    func `'&' given to a parameter that owns its argument names the parameter's type`(
        statement: String, column: Int, callee: String, type: String,
    ) {
        #expect(messages(of: statement) == [
            "\(column): error[E0284]: '\(callee)' takes \(type), not a reference; remove the '&'",
        ])
    }

    @Test(arguments: [
        ("var x = &a + 1", [13]), ("a = &a", [9]), ("_ = &e", [9]), ("if &c {}", [8]),
        ("a = if c { &a } else { &a }", [16, 28]), ("let s: [1 of Int] = [&a]", [26]),
    ])
    func `'&' outside a call's arguments and a 'ref let' is reported as unsupported`(
        statement: String, columns: [Int],
    ) {
        #expect(messages(of: statement) == columns.map {
            "\($0): error[E0285]: '&' isn't supported outside a call's arguments and a 'ref let'"
        })
    }

    @Test(arguments: [
        ("show(mutable &e)", 10), ("read(mutable &e.stats.hp)", 10), ("take(mutable &a)", 10), ("_ = mutable &a", 9),
        ("let x = mutable &a", 13), ("a = mutable &a", 9),
    ])
    func `'mutable &' outside a 'ref let' or 'ref var' is reported as unsupported`(statement: String, column: Int) {
        #expect(messages(of: statement) == ["\(column): error[E0289]: 'mutable &' isn't supported"])
    }

    @Test func `a call that fails for its arguments' count reports nothing of a '&' among them`() {
        #expect(messages(of: "show(&e, &e)") == ["5: error[E0210]: 'show' takes 1 argument, but the call passes 2"])
    }

    @Test(arguments: ["func f(_ x: &Nope) {}", "func f(_ x: &Nope) {}\nfunc f(_ x: Bool) {}"])
    func `an argument whose parameter's type isn't known reports nothing of its '&'`(declarations: String) {
        let source = "func main() {\n    var a = 1\n    f(&a)\n}\n\(declarations)"
        #expect(errors(source) == [.notAType(name: "Nope")])
    }

    @Test(arguments: ["func f(_ n: Int, _ u: UInt, _ b: Bool) {}", "func f(_ e: &Enemy, _ s: &[2 of Enemy]) {}"])
    func `a parameter may own an Int, a UInt or a Bool, and borrow a value of any type`(declaration: String) {
        #expect(declarationMessages(of: declaration) == [])
    }

    @Test(arguments: [
        ("func f(_ e: Enemy) {}", "3:13", "an Enemy", "Enemy"),
        ("func f(_ s: [2 of Int]) {}", "3:13", "a [2 of Int]", "[2 of Int]"),
    ])
    func `a parameter that owns a struct or an array names v0.3, and says to borrow it`(
        declaration: String, position: String, type: String, written: String,
    ) {
        #expect(declarationMessages(of: declaration) == [
            "\(position): error[E0282]: parameters that own \(type) arrive in v0.3; write '&\(written)' to borrow it",
        ])
    }

    @Test func `a call of a function whose parameter owns a struct reports nothing more`() {
        let body = "    var e = Enemy(hp: 1)\n    f(e)\n    f(&e)\n    print(e.hp)"
        let source = "func main() {\n\(body)\n}\nstruct Enemy(var hp: Int)\nfunc f(_ e: Enemy) { print(e.hp) }"
        #expect(errors(source) == [.unsupportedOwnedParameter(type: "Enemy")])
    }

    @Test func `a 'mutable &T' parameter is reported as unsupported`() {
        #expect(declarationMessages(of: "func f(_ e: mutable &Enemy) {}") == [
            "3:8: error[E0232]: 'mutable &' parameters aren't supported",
        ])
    }

    @Test func `a call of a function whose parameter is 'mutable &T' reports nothing more`() {
        let body = "    var x = 1\n    bump(x)\n    bump(&x)\n    print(x)"
        let source = "func main() {\n\(body)\n}\nfunc bump(_ n: mutable &Int) {}"
        #expect(errors(source) == [.unsupportedConvention(convention: "mutable &")])
    }

    @Test func `a parameter that owns an Int may change, and one that borrows it can't`() {
        #expect(declarationMessages(of: "func f(_ n: Int) {\n    n += 1\n    print(n)\n}") == [])
        #expect(declarationMessages(of: "func f(_ n: &Int) { n = 1 }") == [
            "3:21: error[E0230]: 'n' is a borrowed parameter, so it can't change",
        ])
    }
}
