import Testing
import RayoDiagnostics

/// Two structs, one holding the other.
private let shotAndHit = "\nstruct Shot(var hit: Hit)\nstruct Hit(var damage: Int)"

struct StructTests {
    @Test(arguments: [
        ("let i: Int = copy s", ErrorCode.typeMismatch(expected: "Int", found: "S")),
        ("let e: E = copy s", .typeMismatch(expected: "E", found: "S")),
        ("print(s)", .noMatchingFunction(name: "print", arguments: "S")),
        ("let t = s + s", .operandTypes(op: "+", needs: "Int", left: "S", right: "S")),
        ("let b = s == s", .incomparable(op: "==", type: "S")),
    ])
    func `a value of a struct's type has no other type, and '==' can't compare it`(body: String, expected: ErrorCode) {
        #expect(errors("func main() {}\nfunc f(_ s: S) {\n\(body)\n}\nstruct S(var a: Int)\nstruct E") == [expected])
    }

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

    @Test(arguments: [
        ("let s = S", ErrorCode.typeAsValue(name: "S")),
        ("S = 1", .assignToType(name: "S")),
    ])
    func `a struct's name used as a value or an assignment's target is reported as a struct's`(
        body: String, expected: ErrorCode,
    ) {
        let source = "func main() {\n\(body)\n}\nstruct S(var a: Int)"

        // The one error covers the struct's name.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == ["S"])
    }

    @Test(arguments: [
        ("let x: Int = 1", "struct Int(var big: Bool)",
         [ErrorCode.typeMismatch(expected: "Int", found: .shadowedPrelude("Int"))]),
        ("print(1)", "struct print", [.argumentNamesNoField(type: "print")]),
    ])
    func `a struct's name shadows the prelude's type or function of that name`(
        body: String, declaration: String, expected: [ErrorCode],
    ) {
        #expect(errors("func main() {\n\(body)\n}\n\(declaration)") == expected)
    }

    @Test(arguments: [
        ("let b: Bool = 1", ErrorCode.typeMismatch(expected: "Bool", found: .shadowedPrelude("Int"))),
        ("1", .unusedValue(value: TypedValue(type: .shadowedPrelude("Int")))),
        ("let b = 1 == true", .operandsDiffer(op: "==", left: .shadowedPrelude("Int"), right: "Bool")),
        ("let t = true + true", .operandTypes(op: "+", needs: .shadowedPrelude("Int"), left: "Bool", right: "Bool")),
        ("_ = g() == g()", .incomparable(op: "==", type: .shadowedPrelude("Void"))),
        ("let y = (1).big", .noSuchField(type: .shadowedPrelude("Int"), field: "big")),
        ("f(1)", .noMatchingFunction(name: "f", arguments: "the prelude's Int")),
        ("let s = S(a: 1)", .fieldTypeMismatch(field: "a", expected: "Bool", found: .shadowedPrelude("Int"))),
    ])
    func `an error names a prelude type that a struct shadows as the prelude's`(body: String, expected: ErrorCode) {
        let structs = "struct Int(var big: Bool)\nstruct Void\nstruct S(var a: Bool)"
        let functions = "func f(_ b: Bool) {}\nfunc f(_ s: S) {}\nfunc g() {}"
        #expect(errors("func main() {\n\(body)\n}\n\(structs)\n\(functions)") == [expected])
    }
}

struct StructDeclarationTests {
    @Test(arguments: [
        ("struct S(var a: Q)", ErrorCode.notAType(name: "Q"), "Q"),
        ("struct S(var a: Void)", .voidField, "Void"),
        ("struct S(var a: ())", .voidField, "()"),
        ("struct S(var a)", .missingFieldType(name: "a"), "a"),
        ("struct S(var a: Int, let a: Bool)", .alreadyDeclared(name: "a"), "a"),
        ("struct S(var _: Int)", .underscoreDeclared, "_"),
        ("struct S(var a: Int = 1)", .fieldDefault, "1"),
        ("struct S(var a = 1 + 2)", .fieldDefault, "1 + 2"),
    ])
    func `a field has a name of its own, a type that isn't Void and no default, and the error covers what is wrong`(
        declaration: String, expected: ErrorCode, covered: String,
    ) {
        let source = "func main() {}\n" + declaration

        // The one error is the field's, and it covers what is wrong with it.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test(arguments: [
        "struct S\nstruct S(var a: Int)", "struct S\nfunc S() {}", "func S() {}\nstruct S",
    ])
    func `a name at a file's top level names one struct, or functions, and the error covers the later name`(
        declarations: String,
    ) {
        let source = "func main() {}\n" + declarations

        // The one error is at the later of the two declarations, on the file's third line.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.alreadyDeclared(name: "S")])
        #expect(reported.map(\.range.start.line) == [3])
    }

    @Test(arguments: [
        ("func main() {}\nfunc S() {}\nstruct S\nfunc g(_ s: S) {}", "S"),
        ("func main() {}\nfunc S() {}\nstruct S\nfunc S(_ x: Int) {}", "S"),
        ("func main() {\n    S()\n}\nstruct S\nfunc S() {}", "S"),
        ("struct main\nfunc main() {}", "main"),
    ])
    func `a struct or function whose name is taken is still declared, so its uses raise no error of their own`(
        source: String, name: String,
    ) {
        #expect(errors(source) == [.alreadyDeclared(name: name)])
    }

    @Test(arguments: [
        ("struct A\nfunc A() {}", "let q = A", ErrorCode.typeAsValue(name: "A")),
        ("struct A\nfunc A() {}", "A = 3", .assignToType(name: "A")),
        ("func A() {}\nstruct A", "let q = A", .functionAsValue(name: "A")),
        ("func A() {}\nstruct A", "A = 3", .assignToFunction(name: "A")),
    ])
    func `a body's use of a taken name, other than a call, finds the kind that declares the name first`(
        declarations: String, body: String, expected: ErrorCode,
    ) {
        #expect(errors("func main() {\n\(body)\n}\n" + declarations) == [expected, .alreadyDeclared(name: "A")])
    }

    @Test func `each function after a struct of its name is an error, though it overloads another`() {
        let reported = diagnostics("func main() {}\nstruct f\nfunc f() {}\nfunc f(_ x: Int) {}")
        #expect(reported.map(\.code) == [.alreadyDeclared(name: "f"), .alreadyDeclared(name: "f")])
        #expect(reported.map(\.range.start.line) == [3, 4])
    }

    @Test func `'_' can't name a struct`() {
        #expect(errors("func main() {}\nstruct _") == [.underscoreDeclared])
    }

    @Test(arguments: [
        ("struct C(var next: C)", ["C"]),
        ("struct A(var b: B)\nstruct B(var a: A)", ["A", "B"]),
        ("struct A(var b: B)\nstruct B(var c: C)\nstruct C(var b: B)", ["B", "C"]),
    ])
    func `a struct can't contain itself, through its fields at any depth, and each struct in the cycle is an error`(
        declarations: String, names: [String],
    ) {
        let source = "func main() {}\n" + declarations

        // Each error covers the name of a struct on the cycle.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == names.map { .containsItself(name: $0) })
        #expect(coveredText(reported, in: source) == names)
    }
}

/// A struct of two Int fields, whose layout keeps their declaration order.
private let enemy = "\nstruct Enemy(var hp: Int, let armor: Int)"

struct StructInitializerTests {
    @Test(arguments: [
        "_ = Enemy(hp: 1, armor: 2)", "_ = Enemy(\n    hp: 1,\n    armor: 2,\n)", "_ = Empty()",
        "let hp = 1\n_ = Enemy(hp: copy hp, armor: 2)\nprint(hp)",
    ])
    func `a call of a struct's name gives each field's value, labeled, in order, and makes the struct`(body: String) {
        #expect(errors("func main() {\n\(body)\n}" + enemy + "\nstruct Empty") == [])
    }

    @Test(arguments: [
        ("_ = Enemy(hp: 1)", [ErrorCode.fieldLeftOut(field: "armor")], ["Enemy(hp: 1)"]),
        ("_ = Enemy()", [.fieldLeftOut(field: "hp"), .fieldLeftOut(field: "armor")], ["Enemy()", "Enemy()"]),
        ("_ = Enemy(hp: 1, armor: 2, speed: 3)", [.noSuchField(type: "Enemy", field: "speed")], ["speed: 3"]),
        ("_ = Enemy(hp: 1, armor: 2, 3)", [.argumentNamesNoField(type: "Enemy")], ["3"]),
        ("_ = Enemy(hp: 1, hp: 2, armor: 3)", [.fieldGivenTwice(field: "hp")], ["hp: 2"]),
        ("_ = Enemy(hp: 1, armr: 2)", [.argumentLabel(expected: .label("armor"), found: .label("armr"))], ["armr: 2"]),
        ("_ = Enemy(1, armor: 2)", [.argumentLabel(expected: .label("hp"), found: .none)], ["1"]),
        ("_ = Enemy(armor: 2, hp: 1)", [.fieldOutOfOrder(field: "hp", after: "armor")], ["hp: 1"]),
        ("_ = Enemy(hp: true, armor: 2)", [.fieldTypeMismatch(field: "hp", expected: "Int", found: "Bool")], ["true"]),
        (
            "_ = Enemy(armor: 2, hq: 1)",
            [.fieldLeftOut(field: "hp"), .noSuchField(type: "Enemy", field: "hq")], ["Enemy(armor: 2, hq: 1)", "hq: 1"],
        ),
    ] as [(String, [ErrorCode], [String])])
    func `a call that doesn't give each field once, labeled and in order, is an error that names the field`(
        body: String, expected: [ErrorCode], covered: [String],
    ) {
        let source = "func main() {\n\(body)\n}" + enemy

        // Each error covers the call where a field is left out, and otherwise the argument or its value.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == expected)
        #expect(coveredText(reported, in: source) == covered)
    }

    @Test(arguments: [
        ("func main() {\nlet hp = 1\n_ = Enemy(hp: hp, armor: 2)\nprint(hp)\n}", ErrorCode.usedAfterMove(name: "hp")),
        ("func main() {}\nfunc f(hp: Int) -> Enemy { Enemy(hp: hp, armor: 2) }", .moveFromParameter(name: "hp")),
        ("func main() {}\nfunc f(e: Enemy) -> Enemy { Enemy(hp: e.hp, armor: 2) }", .fieldMove),
    ])
    func `the initializer takes each argument owned, so it moves a local, and can't take a parameter or a field`(
        source: String, expected: ErrorCode,
    ) {
        #expect(errors(source + enemy) == [expected])
    }

    @Test func `a call of a struct whose field failed checks only its arguments, so the failure doesn't spread`() {
        #expect(errors("func main() {\n_ = S(a: true, b: Q)\n}\nstruct S(var a: Q)") == [
            .notDeclared(name: "Q"), .notAType(name: "Q"),
        ])
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
        ("print(e.speed)", ErrorCode.noSuchField(type: "Enemy", field: "speed"), "speed"),
        ("print(e.0)", .noSuchField(type: "Enemy", field: "0"), "0"),
        ("print(e.0_07)", .noSuchField(type: "Enemy", field: "0_07"), "0_07"),
        ("print(e.hp.armor)", .noSuchField(type: "Int", field: "armor"), "armor"),
        ("let b: Bool = e.hp + 1", .typeMismatch(expected: "Bool", found: "Int"), "e.hp + 1"),
        ("let f = e\nprint(e.hp)", .usedAfterMove(name: "e"), "e.hp"),
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
    func `a declaration, an assignment, a 'return' or '_ =' can't take a field, which would move it`(
        body: String, covered: String,
    ) {
        let source = "func main() {}\nfunc f(e: Enemy) -> Int {\n\(body)\nreturn 0\n}" + enemy

        // The one error covers the field the statement takes.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.fieldMove])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test func `a field whose declaration failed is read with no error of its own`() {
        #expect(errors("func main() {}\nfunc f(s: S) { print(s.a) }\nstruct S(var a: Q)") == [.notAType(name: "Q")])
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
        ("let h = copy e.speed", ErrorCode.noSuchField(type: "Enemy", field: "speed"), "speed"),
        ("let h = copy e.hp.armor", .noSuchField(type: "Int", field: "armor"), "armor"),
        ("let b: Bool = copy e.hp", .typeMismatch(expected: "Bool", found: "Int"), "copy e.hp"),
        ("copy e.hp", .unusedValue(value: TypedValue(type: "Int")), "copy e.hp"),
        ("let f = e\nlet h = copy e.hp\nprint(h + f.hp)", .usedAfterMove(name: "e"), "copy e.hp"),
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
        ("print(e.stats.mana)", ErrorCode.noSuchField(type: "Stats", field: "mana"), "mana"),
        ("print(b.minion.stats.mana)", .noSuchField(type: "Stats", field: "mana"), "mana"),
        ("print(e.stats.hp.mana)", .noSuchField(type: "Int", field: "mana"), "mana"),
        ("let h = e.stats.hp", .fieldMove, "e.stats.hp"),
        ("_ = Enemy(stats: e.stats, armor: 1)", .fieldMove, "e.stats"),
        ("_ = Enemy(stats: e, armor: 1)", .fieldTypeMismatch(field: "stats", expected: "Stats", found: "Enemy"), "e"),
        ("_ = Enemy(stats: Stats(hp: 1), armor: 1)", .fieldLeftOut(field: "speed"), "Stats(hp: 1)"),
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
