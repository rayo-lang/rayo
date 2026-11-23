import Testing

/// A struct, and functions that make one, an array of them and an Int, which the bodies below assign into.
private let declarations = """
    struct Enemy(var hp: Int)
    func makeEnemy() -> Enemy { Enemy(hp: 100) }
    func spawn(hp: Int) -> Enemy { Enemy(hp: hp) }
    func makeEnemies() -> [2 of Enemy] { [makeEnemy(), makeEnemy()] }
    func makeHP() -> Int { 100 }
    """

struct TemporaryAssignmentTests {
    @Test(arguments: [
        ("makeEnemy().hp = 0", "2:1: error[E0291]: 'makeEnemy()' is a temporary; keep it in a 'var'"),
        ("makeEnemy().hp += 1", "2:1: error[E0291]: 'makeEnemy()' is a temporary; keep it in a 'var'"),
        ("makeEnemies()[1].hp = 0", "2:1: error[E0291]: 'makeEnemies()' is a temporary; keep it in a 'var'"),
        ("makeHP() = 1", "2:1: error[E0291]: 'makeHP()' is a temporary; keep it in a 'var'"),
        ("makeHP() -= 1", "2:1: error[E0291]: 'makeHP()' is a temporary; keep it in a 'var'"),
        ("[1, 2][0] = 3", "2:1: error[E0291]: '[1, 2]' is a temporary; keep it in a 'var'"),
    ])
    func `an assignment into a temporary, whole or part, names it and says to keep it in a 'var'`(
        body: String, expected: String,
    ) {
        #expect(errorLines(inMain: body, beside: declarations) == [expected])
    }

    @Test(arguments: [
        ("  spawn(hp:  1+2).hp = 0", "2:3", "spawn(hp: 1+2)"),
        ("spawn(hp: 1 +\n    2).hp = 0", "2:1", "spawn(hp: 1 + 2)"),
        ("spawn(hp: /* full */ 100).hp = 0", "2:1", "spawn(hp: 100)"),
        ("spawn(\n    hp: 1\n).hp = 0", "2:1", "spawn(hp: 1)"),
        ("[ 1 , 2 ][0] = 3", "2:1", "[1, 2]"),
        ("(makeEnemy()).hp = 0", "2:1", "makeEnemy()"),
        ("((makeEnemy())).hp = 0", "2:1", "makeEnemy()"),
        ("(makeHP()) + (makeHP()) = 1", "2:1", "(makeHP()) + (makeHP())"),
    ])
    func `the temporary is named as the source writes it, on one line, without comments or parentheses around it`(
        body: String, position: String, temporary: String,
    ) {
        let expected = "\(position): error[E0291]: '\(temporary)' is a temporary; keep it in a 'var'"
        #expect(errorLines(inMain: body, beside: declarations) == [expected])
    }

    @Test func `a temporary that fails is reported for that alone`() {
        #expect(errorLines(inMain: "nope() = 1", beside: declarations)
            == ["2:1: error[E0206]: 'nope' isn't declared"])
    }

    @Test func `the value is checked even where the temporary can't be assigned`() {
        #expect(errorLines(inMain: "makeEnemy().hp = nope", beside: declarations) == [
            "2:1: error[E0291]: 'makeEnemy()' is a temporary; keep it in a 'var'",
            "2:18: error[E0206]: 'nope' isn't declared",
        ])
    }
}
