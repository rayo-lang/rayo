import Testing
import RayoDiagnostics

/// A struct that holds a struct and is held by another, a function that makes one, and a function that borrows one.
private let enemyAndStats = """

    func made() -> Enemy { Enemy(stats: Stats(hp: 100, speed: 3), armor: 5) }
    func strength(_ e: Enemy) -> Int { e.stats.hp + e.armor }
    struct Boss(var minion: Enemy)
    struct Enemy(var stats: Stats, var armor: Int)
    struct Stats(var hp: Int, var speed: Int)
    """

/// A program whose `f` holds the `let` `l` and the `var` `e`, runs `body`, then reads each one's `armor`.
private func source(running body: String) -> String {
    "func main() {}\nfunc f() {\nlet l = made()\nvar e = made()\n\(body)\nprint(l.armor + e.armor)\n}" + enemyAndStats
}

struct FieldMoveTests {
    @Test(arguments: [
        ("l.stats = Stats(hp: 50, speed: 1)", ErrorCode.assignToPartOfLet(name: "l")),
    ])
    func `a 'let' that a field was moved out of stays partly moved, since its field can't be assigned`(
        body: String, expected: ErrorCode,
    ) {
        #expect(errors(source(running: "let s = l.stats\nprint(s.hp)\n\(body)")) == [expected])
    }
}
