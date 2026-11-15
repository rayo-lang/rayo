import Testing
import RayoDiagnostics

/// Two structs, one holding the other.
private let shotAndHit = "\nstruct Shot(var hit: Hit)\nstruct Hit(var damage: Int)"

struct StructTests {
    @Test(arguments: [
        ("func f(_ s: Shot) -> Shot { s }", "s"),
        ("func f(_ s: Shot) {\n    _ = s\n}", "s"),
        ("func f(_ h: Hit) -> Shot { Shot(hit: h) }", "h"),
    ])
    func `a borrowed parameter of a struct type can't be moved, and the error covers the parameter`(
        declaration: String, name: String,
    ) {
        let source = "func main() {}\n\(declaration)" + shotAndHit

        // The one error is the move, and it covers the parameter's name.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.moveFromParameter(name: name)])
        #expect(coveredText(reported, in: source) == [name])
    }
}

/// A struct of two Int fields, whose layout keeps their declaration order.
private let enemy = "\nstruct Enemy(var hp: Int, let armor: Int)"

struct StructInitializerTests {
    @Test(arguments: [
        "let hp = 1\n_ = Enemy(hp: copy hp, armor: 2)\nprint(hp)",
    ])
    func `a call of a struct's name gives each field's value, labeled, in order, and makes the struct`(body: String) {
        #expect(errors("func main() {\n\(body)\n}" + enemy + "\nstruct Empty") == [])
    }

    @Test(arguments: [
        ("func main() {\nlet hp = 1\n_ = Enemy(hp: hp, armor: 2)\nprint(hp)\n}", ErrorCode.usedAfterMove(name: "hp")),
        ("func main() {}\nfunc f(hp: Int) -> Enemy { Enemy(hp: hp, armor: 2) }", .moveFromParameter(name: "hp")),
        (
            "func main() {}\nfunc f(e: Enemy) -> Enemy { Enemy(hp: e.hp, armor: 2) }",
            .moveFieldFromParameter(field: "e.hp", parameter: "e"),
        ),
    ])
    func `the initializer takes each argument owned, so it moves a local, and can't take a parameter or its field`(
        source: String, expected: ErrorCode,
    ) {
        #expect(errors(source + enemy) == [expected])
    }
}

struct FieldReadTests {
    @Test(arguments: [
        "func main() {\nlet e = Enemy(hp: 1, armor: 2)\nprint(e.hp - e.armor)\nprint(e.hp)\n}",
        "func main() {}\nfunc f(e: Enemy) -> Int { -e.armor }",
        "func main() {}\nfunc f(e: Enemy) -> Bool { e.hp > 0 && f(e: e) }",
        "func main() {\nprint(Enemy(hp: 1, armor: 2).hp)\n}",
    ])
    func `a field of a local, a parameter or a value is read where a borrow suffices, leaving the struct whole`(
        source: String,
    ) {
        #expect(errors(source + enemy) == [])
    }

    @Test(arguments: [
        ("let f = e\nprint(e.hp)", ErrorCode.usedAfterMove(name: "e"), "e.hp"),
    ])
    func `a read of a field the value doesn't have, or of a moved struct, is an error`(
        body: String, expected: ErrorCode, covered: String,
    ) {
        let source = "func main() {\nlet e = Enemy(hp: 1, armor: 2)\n\(body)\n}" + enemy

        // The one error names the type and the field where the field is missing, and covers what is wrong.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test(arguments: [
        ("let h = e.hp", "e.hp"), ("_ = e.hp", "e.hp"), ("var h = 0\nh = e.hp", "e.hp"), ("return e.hp", "e.hp"),
        ("return (e.hp)", "(e.hp)"),
    ])
    func `a declaration, an assignment, a 'return' or '_ =' can't take a borrowed parameter's field, which it moves`(
        body: String, covered: String,
    ) {
        let source = "func main() {}\nfunc f(e: Enemy) -> Int {\n\(body)\nreturn 0\n}" + enemy

        // The one error covers the field the statement takes.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.moveFieldFromParameter(field: "e.hp", parameter: "e")])
        #expect(coveredText(reported, in: source) == [covered])
    }
}

struct FieldCopyTests {
    @Test(arguments: [
        "let h = copy e.hp\nprint(h)", "_ = copy e.armor", "var h = 0\nprint(h)\nh = copy e.hp\nprint(h)",
        "return copy e.hp", "return (copy e.hp)", "return copy e.hp + copy e.armor",
        "_ = Enemy(hp: copy e.hp, armor: 1)", "let h = copy e.hp\nlet k = copy e\nprint(h + k.armor + e.hp)",
        "let h = copy e.hp\nreturn f(e: e) + h",
    ])
    func `a copy of a field of a borrowed parameter may be taken, and leaves the struct whole`(body: String) {
        #expect(errors("func main() {}\nfunc f(e: Enemy) -> Int {\n\(body)\nreturn 0\n}" + enemy) == [])
    }

    @Test(arguments: [
        ("let f = e\nlet h = copy e.hp\nprint(h + f.hp)", ErrorCode.usedAfterMove(name: "e"), "copy e.hp"),
    ])
    func `a copy of a field the value doesn't have, of a moved struct, or left unused, is an error`(
        body: String, expected: ErrorCode, covered: String,
    ) {
        let source = "func main() {\nlet e = Enemy(hp: 1, armor: 2)\nprint(e.armor)\n\(body)\n}" + enemy

        // The one error names the type and the field where the field is missing, and covers what is wrong.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == [covered])
    }
}

/// A struct that holds a struct that holds a struct.
private let bossEnemyAndStats = """

    struct Boss(var minion: Enemy)
    struct Enemy(var stats: Stats, let armor: Int)
    struct Stats(var hp: Int, var speed: Int)
    """

struct NestedStructTests {
    @Test(arguments: [
        "let made = Enemy(stats: Stats(hp: 1, speed: 2), armor: 3)\nreturn made.stats.hp > made.stats.speed",
        "let s = Stats(hp: 1, speed: 2)\nlet made = Enemy(stats: s, armor: 3)\nreturn made.stats.hp - made.armor > 0",
        "return b.minion.stats.hp > b.minion.armor && f(b: b, e: e)",
        "return fast(e.stats)",
        "return Boss(minion: Enemy(stats: Stats(hp: 1, speed: 2), armor: 3)).minion.stats.speed > 0",
    ])
    func `a field may be a struct, made by a nested call or from a local, and read through where a borrow suffices`(
        body: String,
    ) {
        let functions = "func main() {}\nfunc f(b: Boss, e: Enemy) -> Bool {\n\(body)\n}\n"
        let fast = "func fast(_ s: Stats) -> Bool { s.speed > 1 }"
        #expect(errors(functions + fast + bossEnemyAndStats) == [])
    }

    @Test(arguments: [
        (
            "let h = b.minion.stats.hp", ErrorCode.moveFieldFromParameter(field: "b.minion.stats.hp", parameter: "b"),
            "b.minion.stats.hp",
        ),
        (
            "_ = Enemy(stats: b.minion.stats, armor: 1)",
            .moveFieldFromParameter(field: "b.minion.stats", parameter: "b"), "b.minion.stats",
        ),
        (
            "let s = Stats(hp: 1, speed: 2)\n_ = Enemy(stats: s, armor: 1)\nprint(s.hp)",
            .usedAfterMove(name: "s"), "s.hp",
        ),
    ])
    func `a nested read of no field, a taken field, a wrong or partial field value, or a moved local is an error`(
        body: String, expected: ErrorCode, covered: String,
    ) {
        let madeEnemy = "let e = Enemy(stats: Stats(hp: 1, speed: 2), armor: 3)"
        let source = "func main() {}\nfunc f(b: Boss) {\n\(madeEnemy)\n\(body)\n}" + bossEnemyAndStats

        // The one error covers what is wrong.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == [covered])
    }
}
