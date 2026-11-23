import Testing
import RayoDiagnostics

/// A struct that holds a struct, and a function that makes one.
private let enemyAndStats = """

    func made() -> Enemy { Enemy(stats: Stats(alive: true, hp: 100), armor: 5) }
    struct Enemy(var stats: Stats, var armor: Int)
    struct Stats(let alive: Bool, var hp: Int)
    """

/// A program whose `f` holds the `let` `l` and the `var` `e`, takes the borrowed parameter `p`, and runs `body`.
private func source(running body: String) -> String {
    "func main() {}\nfunc f(_ p: &Enemy) {\nlet l = made()\nvar e = made()\n\(body)\n}" + enemyAndStats
}

struct FieldAssignmentTests {
    @Test(arguments: [
        ("l.armor = 1", ErrorCode.assignToPartOfLet(name: "l"), "l"),
        ("l.stats.hp += 1", .assignToPartOfLet(name: "l"), "l"),
        ("l.stats = Stats(alive: true, hp: 50)", .assignToPartOfLet(name: "l"), "l"),
        ("p.stats.hp = 1", .assignToParameter(name: "p"), "p"),
        ("e.stats.alive = false", .assignToLetField(field: "alive"), "alive"),
        ("e.stats.mana = 1", .noSuchField(type: "Stats", field: "mana"), "mana"),
        ("e.armor = true", .typeMismatch(expected: "Int", found: "Bool"), "true"),
        ("e.stats = made()", .typeMismatch(expected: "Stats", found: "Enemy"), "made()"),
        ("made().armor = 1", .assignToTemporary(temporary: "made()"), "made()"),
        ("_.armor = 1", .assignToUnderscore, "_"),
        ("Enemy.armor = 1", .assignToType(name: "Enemy"), "Enemy"),
        ("made.armor = 1", .assignToFunction(name: "made"), "made"),
        ("nope.armor = 1", .notDeclared(name: "nope"), "nope"),
        ("Int.armor = 1", .assignToType(name: "Int"), "Int"),
    ])
    func `a field's assignment needs a 'var' local or a 'var' field, and a value of its type`(
        body: String, expected: ErrorCode, covered: String,
    ) {
        let source = source(running: body)

        // The one error covers the binding, the field or the value that is wrong.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test(arguments: [
        ("l.mana = 1", ErrorCode.noSuchField(type: "Enemy", field: "mana"), "mana"),
        ("p.mana = 1", .noSuchField(type: "Enemy", field: "mana"), "mana"),
        ("l.stats.alive = false", .assignToLetField(field: "alive"), "alive"),
        ("made().mana = 1", .noSuchField(type: "Enemy", field: "mana"), "mana"),
        ("nope().armor = 1", .notDeclared(name: "nope"), "nope"),
    ])
    func `what a target names is checked before whether its root may change part by part`(
        body: String, expected: ErrorCode, covered: String,
    ) {
        let source = source(running: body)

        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test(arguments: [
        ("b.stats.hp = 1", ErrorCode.assignToLetField(field: "stats"), "stats"),
        ("b.level *= 2", .assignToLetField(field: "level"), "level"),
        ("b.stats.hp /= 2", .assignToLetField(field: "stats"), "stats"),
    ])
    func `a 'let' field anywhere on the target's path rules out an assignment or a compound one`(
        body: String, expected: ErrorCode, covered: String,
    ) {
        let source = """
            func main() {
            var b = Boss(stats: Stats(alive: true, hp: 1), level: 4)
            \(body)
            }
            struct Boss(let stats: Stats, let level: Int)
            """ + enemyAndStats

        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test func `a 'let' declared without a value is given one whole, never field by field`() {
        let source = "func main() {\nlet l: Enemy\nl.armor = 1\n}" + enemyAndStats
        #expect(errors(source) == [.assignToPartOfLet(name: "l")])
    }

    @Test func `the value is checked even where the field can't be assigned`() {
        let expected: [ErrorCode] = [.assignToPartOfLet(name: "l"), .notDeclared(name: "nope")]
        #expect(errors(source(running: "l.armor = nope")) == expected)
    }
}
