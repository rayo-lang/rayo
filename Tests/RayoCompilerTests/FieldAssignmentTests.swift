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
