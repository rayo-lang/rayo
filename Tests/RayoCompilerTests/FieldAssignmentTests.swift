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
    "func main() {}\nfunc f(_ p: Enemy) {\nlet l = made()\nvar e = made()\n\(body)\n}" + enemyAndStats
}

struct FieldAssignmentTests {
    @Test(arguments: [
        ("l.armor = 1", ErrorCode.assignToFieldOfLet(name: "l"), "l"),
        ("l.stats.hp += 1", .assignToFieldOfLet(name: "l"), "l"),
        ("p.stats.hp = 1", .assignToParameter(name: "p"), "p"),
        ("e.stats.alive = false", .assignToLetField(field: "alive"), "alive"),
        ("e.stats.mana = 1", .noSuchField(type: "Stats", field: "mana"), "mana"),
        ("e.armor = true", .typeMismatch(expected: "Int", found: "Bool"), "true"),
        ("e.stats = made()", .typeMismatch(expected: "Stats", found: "Enemy"), "made()"),
        ("made().armor = 1", .assignToNonLocal, "made()"),
        ("_.armor = 1", .assignToNonLocal, "_"),
        ("Enemy.armor = 1", .assignToType(name: "Enemy"), "Enemy"),
        ("made.armor = 1", .assignToFunction(name: "made"), "made"),
        ("nope.armor = 1", .notDeclared(name: "nope"), "nope"),
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

    @Test func `a 'let' declared without a value is given one whole, never field by field`() {
        let source = "func main() {\nlet l: Enemy\nl.armor = 1\n}" + enemyAndStats
        #expect(errors(source) == [.assignToFieldOfLet(name: "l")])
    }

    @Test func `the value is checked even where the field can't be assigned`() {
        let expected: [ErrorCode] = [.assignToFieldOfLet(name: "l"), .notDeclared(name: "nope")]
        #expect(errors(source(running: "l.armor = nope")) == expected)
    }

    @Test func `taking a field to assign it to another moves it out of its struct`() {
        let expected: [ErrorCode] = [.usedAfterMove(name: "l.stats")]
        #expect(errors(source(running: "e.stats = l.stats\nprint(e.stats.hp + l.stats.hp)")) == expected)
    }

    @Test(arguments: [
        ("print(e.armor)\ne.stats.hp = 1", "e.stats.hp"),
        ("e.armor = 1\nprint(e.stats.hp)", "e.armor"),
    ])
    func `a value assigned to a field that no code reads is an error that covers the field's path`(
        body: String, path: String,
    ) {
        let source = "func main() {\nvar e = made()\n\(body)\n}" + enemyAndStats

        // The one error names the path, and covers it as the assignment writes it.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.unreadValue(name: path)])
        #expect(coveredText(reported, in: source) == [path])
    }
}
