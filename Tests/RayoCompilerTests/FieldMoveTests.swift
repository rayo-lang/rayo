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
        "let s = e.stats\nprint(s.hp)\nprint(e.armor)",
        "let s = e.stats\nprint(s.hp)\nlet a = copy e.armor\ne.armor = a + 1\nlet b = e.armor\nprint(b)\ne.armor = 0",
        "let s = l.stats\nprint(s.hp + l.armor)",
        "let h = e.stats.hp\nprint(h + e.stats.speed + e.armor)",
        "_ = Enemy(stats: e.stats, armor: 1)\nprint(e.armor)",
        "var s = Stats(hp: 1, speed: 2)\nprint(s.hp)\ns = l.stats\nprint(s.hp)",
        "e.stats = l.stats\nprint(e.stats.hp)",
        "let s = made().stats\nprint(s.hp)",
    ])
    func `a field moves out of a local or a temporary, and the struct's other fields stay readable`(body: String) {
        #expect(errors(source(running: body)) == [])
    }

    @Test(arguments: [
        ("_ = e\ne = made()", ErrorCode.usedPartlyMoved(name: "e", field: "e.stats"), "e"),
        ("_ = Boss(minion: e)\ne = made()", .usedPartlyMoved(name: "e", field: "e.stats"), "e"),
        ("let c = copy e\nprint(c.armor)", .usedPartlyMoved(name: "e", field: "e.stats"), "copy e"),
        ("print(strength(e))", .usedPartlyMoved(name: "e", field: "e.stats"), "e"),
        ("print(e.stats.hp)", .usedAfterMove(name: "e.stats"), "e.stats.hp"),
        ("let t = e.stats\nprint(t.hp)", .usedAfterMove(name: "e.stats"), "e.stats"),
        ("let t = copy e.stats\nprint(t.hp)", .usedAfterMove(name: "e.stats"), "copy e.stats"),
        ("e.stats.hp = 1", .usedAfterMove(name: "e.stats"), "e.stats.hp"),
    ])
    func `a struct that a field was moved out of can't be used whole, nor the field read, until it is assigned`(
        body: String, expected: ErrorCode, covered: String,
    ) {
        let source = source(running: "let s = e.stats\nprint(s.hp)\n\(body)")

        // The one error names the moved field, and covers the use.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test(arguments: ["e.stats = Stats(hp: 50, speed: 1)", "e = made()"])
    func `assigning the moved field, or the whole struct, makes the struct whole again`(assignment: String) {
        let body = "let s = e.stats\nprint(s.hp)\n\(assignment)\nprint(strength(e))\nlet t = e.stats\nprint(t.hp)"
        #expect(errors(source(running: body)) == [])
    }

    @Test(arguments: [
        ("print(strength(e))", ErrorCode.usedMaybePartlyMoved(name: "e", field: "e.stats"), "e"),
        ("print(e.stats.speed)", .usedAfterMaybeMove(name: "e.stats"), "e.stats.speed"),
        ("let t = copy e.stats\nprint(t.hp)", .usedAfterMaybeMove(name: "e.stats"), "copy e.stats"),
    ])
    func `a field moved in one branch may have been moved after it, so it and its struct can't be used`(
        body: String, expected: ErrorCode, covered: String,
    ) {
        let source = source(running: "if e.armor > 1 {\nlet s = e.stats\nprint(s.hp)\n}\n\(body)")

        // The one error names the field that may have been moved, and covers the use.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test func `a field moved in a loop's body may have been moved on the next pass, unless the body assigns it`() {
        let loop = "while e.armor > 0 {\nlet s = e.stats\nprint(s.hp)\ne.armor -= 1\n"
        let movingLoop = source(running: loop + "}")

        // The one error is at the move, which the pass before may have made.
        let reported = diagnostics(movingLoop)
        #expect(reported.map(\.code) == [.usedAfterMaybeMove(name: "e.stats")])
        #expect(coveredText(reported, in: movingLoop) == ["e.stats"])
        #expect(errors(source(running: loop + "e.stats = s\n}")) == [])
    }

    @Test func `a 'return' moves a field out of a local`() {
        #expect(errors("func main() {}\nfunc g() -> Stats {\nlet e = made()\nreturn e.stats\n}" + enemyAndStats) == [])
    }

    @Test(arguments: [
        ("l.stats = Stats(hp: 50, speed: 1)", ErrorCode.assignToPartOfLet(name: "l")),
        ("print(strength(l))", .usedPartlyMoved(name: "l", field: "l.stats")),
    ])
    func `a 'let' that a field was moved out of stays partly moved, since its field can't be assigned`(
        body: String, expected: ErrorCode,
    ) {
        #expect(errors(source(running: "let s = l.stats\nprint(s.hp)\n\(body)")) == [expected])
    }

    @Test(arguments: [
        ("let s = p.stats\nprint(s.hp)", "p.stats"), ("_ = p.stats.hp", "p.stats.hp"),
        ("let s = p.stats\nprint(s.hp)\nprint(p.stats.hp)", "p.stats"),
        ("_ = Boss(minion: Enemy(stats: p.stats, armor: 1))", "p.stats"),
    ])
    func `a field of a borrowed parameter can't be moved out, and the error names the field and the parameter`(
        body: String, field: String,
    ) {
        let source = "func main() {}\nfunc g(_ p: Enemy) {\n\(body)\n}" + enemyAndStats

        // The one error covers the field the statement takes.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.moveFieldFromParameter(field: field, parameter: "p")])
        #expect(coveredText(reported, in: source) == [field])
    }
}
