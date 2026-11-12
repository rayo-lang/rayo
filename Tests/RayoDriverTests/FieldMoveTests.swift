import Testing
import RayoDriver

/// A struct that holds a struct, and functions that make one and borrow one. `Enemy` and `Stats` each lay `alive` out
/// after its Ints, so a move out of the wrong element at either level gives another field's value.
private let enemyAndStats = """

    func enemy() -> Enemy { Enemy(alive: true, stats: Stats(alive: true, hp: 100, speed: 3), armor: 5) }
    func strength(_ e: Enemy) -> Int { e.stats.hp * e.armor }
    struct Enemy(let alive: Bool, var stats: Stats, var armor: Int)
    struct Stats(let alive: Bool, var hp: Int, var speed: Int)
    """

struct FieldMoveTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `a field moved out of a local holds its value, and the struct's other fields keep theirs, in both builds`(
        mode: [String],
    ) {
        // `e` is a `var`, whose other fields are copied, assigned and moved in turn, and `l` a `let`; `l`'s `hp` moves
        // out of the struct inside it, and `made`'s `stats` out of a call's result.
        let source = """
            func main() {
                var e = enemy()
                let s = e.stats
                print(s.hp)
                print(s.speed)
                print(e.armor)
                print(e.alive)
                let armor = copy e.armor
                e.armor = armor + 1
                let moved = e.armor
                print(moved)
                let l = Enemy(alive: false, stats: Stats(alive: true, hp: 20, speed: 7), armor: 2)
                let hp = l.stats.hp
                print(hp)
                print(l.stats.speed)
                print(l.armor)
                let made = Enemy(alive: true, stats: enemy().stats, armor: 9)
                print(made.stats.hp)
            }
            """ + enemyAndStats
        let output = "100\n3\n5\ntrue\n6\n20\n7\n2\n100\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: output, errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `assigning the moved field makes the struct whole again, to be used whole with the new value, in both builds`(
        mode: [String],
    ) {
        let source = """
            func main() {
                var e = enemy()
                let s = e.stats
                print(s.hp)
                e.stats = Stats(alive: false, hp: 50, speed: 1)
                print(strength(e))
                let c = copy e
                print(c.stats.hp)
                let taken = e
                print(taken.stats.speed)
            }
            """ + enemyAndStats
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "100\n250\n50\n1\n", errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]], [
        (["print(strength(e))"], "5:20: error[E0309]: 'e.stats' was moved out of 'e', so 'e' can't be used whole"),
        (
            ["let c = copy e", "print(c.armor)"],
            "5:13: error[E0309]: 'e.stats' was moved out of 'e', so 'e' can't be used whole",
        ),
        (["_ = e"], "5:9: error[E0309]: 'e.stats' was moved out of 'e', so 'e' can't be used whole"),
        (["print(e.stats.hp)"], "5:11: error[E0302]: 'e.stats' was moved"),
        (["let t = e.stats", "print(t.hp)"], "5:13: error[E0302]: 'e.stats' was moved"),
    ])
    func `a struct a field was moved out of can't be used whole, nor the field read, in either build`(
        mode: [String], failure: (lines: [String], error: String),
    ) {
        let lines = ["var e = enemy()", "let s = e.stats", "print(s.hp)"] + failure.lines
        let expected = CommandResult(exitCode: 1, output: "", errors: "main.rayo:\(failure.error)\n")
        #expect(run(main(running: lines), options: mode) == expected)
    }

    @Test(arguments: [["--debug"], ["--release"]], [
        (
            "print(strength(e))",
            "7:20: error[E0310]: 'e.stats' may have been moved out of 'e', so 'e' can't be used whole",
        ),
        ("print(e.stats.speed)", "7:11: error[E0303]: 'e.stats' may have been moved"),
    ])
    func `a field moved in one branch of an 'if' may have been moved after it, in either build`(
        mode: [String], failure: (line: String, error: String),
    ) {
        let lines = ["var e = enemy()", "if e.armor > 1 {", "    let s = e.stats", "    print(s.hp)", "}", failure.line]
        let expected = CommandResult(exitCode: 1, output: "", errors: "main.rayo:\(failure.error)\n")
        #expect(run(main(running: lines), options: mode) == expected)
    }

    @Test(arguments: [["--debug"], ["--release"]], [
        ("l.stats = s", "5:5: error[E0251]: 'l' is a 'let', so its fields can't change"),
        ("print(strength(l))", "5:20: error[E0309]: 'l.stats' was moved out of 'l', so 'l' can't be used whole"),
    ])
    func `a 'let' that a field was moved out of stays partly moved, in either build`(
        mode: [String], failure: (line: String, error: String),
    ) {
        let lines = ["let l = enemy()", "let s = l.stats", "print(s.hp)", failure.line]
        let expected = CommandResult(exitCode: 1, output: "", errors: "main.rayo:\(failure.error)\n")
        #expect(run(main(running: lines), options: mode) == expected)
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `moving a field out of a borrowed parameter is an error that offers a copy, in debug and release`(
        mode: [String],
    ) {
        let source = """
            func main() {}
            func heal(_ e: Enemy) -> Int {
                let s = e.stats
                return s.hp
            }
            """ + enemyAndStats
        let error = "main.rayo:3:13: error[E0311]: 'e.stats' is in the borrowed parameter 'e', so it can't be moved; "
            + "'copy' makes an owned copy\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 1, output: "", errors: error))
    }
}

/// A program whose `main` runs `lines`, one to a line from the second.
private func main(running lines: [String]) -> String {
    "func main() {\n" + lines.map { "    \($0)\n" }.joined() + "}" + enemyAndStats
}
