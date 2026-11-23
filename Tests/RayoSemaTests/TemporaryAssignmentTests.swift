import Testing

/// A struct, and functions that make one, an array of them and an Int, which the bodies below assign into.
private let declarations = """
    struct Enemy(var hp: Int)
    func makeEnemy() -> Enemy { Enemy(hp: 100) }
    func spawn(hp: Int) -> Enemy { Enemy(hp: hp) }
    func makeEnemies() -> [2 of Enemy] { [makeEnemy(), makeEnemy()] }
    func makeHP() -> Int { 100 }
    """

/// The error line for an assignment into `temporary` at `position`.
private func assignedTemporary(_ temporary: String, at position: String = "2:1") -> String {
    "\(position): error[E0291]: changing '\(temporary)' does nothing, since it's dropped right after; store it in a "
        + "'var' first"
}

struct TemporaryAssignmentTests {
    @Test(arguments: [
        ("makeEnemy().hp = 0", "makeEnemy()"),
        ("makeEnemy().hp += 1", "makeEnemy()"),
        ("makeEnemies()[1].hp = 0", "makeEnemies()"),
        ("makeHP() = 1", "makeHP()"),
        ("makeHP() -= 1", "makeHP()"),
        ("[1, 2][0] = 3", "[1, 2]"),
    ])
    func `an assignment into a temporary, whole or part, names it and says to store it in a 'var'`(
        body: String, temporary: String,
    ) {
        #expect(errorLines(inMain: body, beside: declarations) == [assignedTemporary(temporary)])
    }

    @Test(arguments: [
        ("  spawn(hp:  1+2).hp = 0", "2:3", "spawn(hp: 1+2)"),
        ("spawn(hp: 1 +\n    2).hp = 0", "2:1", "spawn(hp: 1 + 2)"),
        ("spawn(hp: /* full */ 100).hp = 0", "2:1", "spawn(hp: 100)"),
        ("spawn(\n    hp: 1\n).hp = 0", "2:1", "spawn(hp: 1)"),
        ("[ 1 , 2 ][0] = 3", "2:1", "[1, 2]"),
        ("spawn( hp: 1 ).hp = 0", "2:1", "spawn(hp: 1)"),
        ("spawn(hp: makeEnemy()\n    .hp).hp = 0", "2:1", "spawn(hp: makeEnemy().hp)"),
        (
            "(if true {\n    print(1)\n    makeEnemy()\n} else { makeEnemy() }).hp = 0", "2:1",
            "if true { print(1); makeEnemy() } else { makeEnemy() }",
        ),
        ("(if true {makeEnemy()} else {makeEnemy()}).hp = 0", "2:1", "if true {makeEnemy()} else {makeEnemy()}"),
        (
            "(if true { print(1) ; makeEnemy() } else { makeEnemy() }).hp = 0", "2:1",
            "if true { print(1); makeEnemy() } else { makeEnemy() }",
        ),
        (
            "(if true {\n    print(1);\n    makeEnemy()\n} else { makeEnemy() }).hp = 0", "2:1",
            "if true { print(1); makeEnemy() } else { makeEnemy() }",
        ),
        ("(makeEnemy()).hp = 0", "2:1", "makeEnemy()"),
        ("((makeEnemy())).hp = 0", "2:1", "makeEnemy()"),
        ("(makeHP()) + (makeHP()) = 1", "2:1", "(makeHP()) + (makeHP())"),
    ])
    func `the temporary is named as the source writes it, on one line, without comments or parentheses around it`(
        body: String, position: String, temporary: String,
    ) {
        #expect(errorLines(inMain: body, beside: declarations) == [assignedTemporary(temporary, at: position)])
    }

    @Test func `a temporary that fails is reported for that alone`() {
        #expect(errorLines(inMain: "nope() = 1", beside: declarations)
            == ["2:1: error[E0206]: 'nope' isn't declared"])
    }

    @Test func `the value is checked even where the temporary can't be assigned`() {
        #expect(errorLines(inMain: "makeEnemy().hp = nope", beside: declarations) == [
            assignedTemporary("makeEnemy()"),
            "2:18: error[E0206]: 'nope' isn't declared",
        ])
    }
}
