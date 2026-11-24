import Testing

/// A struct, functions that make one, an array of them and an Int, and functions that borrow their arguments for
/// change, borrow them, or own them, which the bodies below lend temporaries to.
private let declarations = """
    struct Enemy(var hp: Int, var stats: Stats)
    struct Stats(var armor: Int)
    func makeEnemy() -> Enemy { Enemy(hp: 100, stats: Stats(armor: 1)) }
    func makeEnemies() -> [2 of Enemy] { [makeEnemy(), makeEnemy()] }
    func heal(_ e: mutable &Enemy) {}
    func fortify(_ s: mutable &Stats) {}
    func bump(_ n: mutable &Int) {}
    func show(_ e: &Enemy) {}
    func keep(_ n: Int) { print(n) }
    """

/// The error line for a `mutable` of `temporary` at `position`.
private func lentTemporary(_ temporary: String, at position: String) -> String {
    "\(position): error[E0291]: changing '\(temporary)' does nothing, since it's dropped right after; store it in a "
        + "'var' first"
}

struct MutableTemporaryTests {
    @Test(arguments: [
        ("heal(mutable makeEnemy())", "2:14", "makeEnemy()"),
        ("fortify(mutable makeEnemy().stats)", "2:17", "makeEnemy()"),
        ("bump(mutable makeEnemy().hp)", "2:14", "makeEnemy()"),
        ("heal(mutable makeEnemies()[0])", "2:14", "makeEnemies()"),
        ("bump(mutable 5)", "2:14", "5"),
        ("bump(mutable [1, 2][0])", "2:14", "[1, 2]"),
        ("bump(mutable -5)", "2:14", "-5"),
    ])
    func `'mutable' of a temporary, or of a part of one, names it and says to store it in a 'var'`(
        body: String, position: String, temporary: String,
    ) {
        #expect(errorLines(inMain: body, beside: declarations) == [lentTemporary(temporary, at: position)])
    }

    // The temporary can't change wherever the `mutable` stands, so that is all a position that takes no mutable
    // reference reports of it.
    @Test(arguments: [
        ("show(mutable makeEnemy())", "2:14", "makeEnemy()"),
        ("keep(mutable makeEnemy().hp)", "2:14", "makeEnemy()"),
        ("_ = mutable makeEnemy()", "2:13", "makeEnemy()"),
        ("_ = mutable 5", "2:13", "5"),
        ("let e = mutable makeEnemies()[1]", "2:17", "makeEnemies()"),
        ("ref let e = mutable makeEnemy()", "2:21", "makeEnemy()"),
    ])
    func `'mutable' of a temporary reports it alone, wherever the 'mutable' stands`(
        body: String, position: String, temporary: String,
    ) {
        #expect(errorLines(inMain: body, beside: declarations) == [lentTemporary(temporary, at: position)])
    }

    @Test func `a temporary that fails is reported for that alone`() {
        #expect(errorLines(inMain: "heal(mutable nope())", beside: declarations)
            == ["2:14: error[E0206]: 'nope' isn't declared"])
    }
}
