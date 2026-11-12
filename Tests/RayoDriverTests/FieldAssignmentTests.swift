import Testing
import RayoDriver

/// Two structs that hold a struct, the one in a `var` field and the other in a `let` one. `Enemy` and `Stats` each lay
/// `alive` out after its Ints, so an assignment that stores into the wrong element at either level changes another
/// field.
private let enemyAndStats = """

    struct Enemy(let alive: Bool, var stats: Stats, var armor: Int)
    struct Stats(let alive: Bool, var hp: Int, var speed: Int)
    struct Boss(let stats: Stats, var armor: Int)
    """

struct FieldAssignmentTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `an assigned field gives a later read its new value, and the other fields keep theirs, in debug and release`(
        mode: [String],
    ) {
        let source = """
            func main() {
                var e = Enemy(alive: true, stats: Stats(alive: true, hp: 100, speed: 3), armor: 5)
                e.armor = 9
                print(e.armor)
                e.stats.hp = 90
                print(e.stats.hp)
                print(e.stats.speed)
                print(e.stats.alive)
                print(e.alive)
                print(e.armor)
            }
            """ + enemyAndStats
        let output = "9\n90\n3\ntrue\ntrue\n9\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: output, errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `a struct-typed field assigned whole holds the new struct, and the other fields keep theirs, in both builds`(
        mode: [String],
    ) {
        // The new `Stats` comes from a call, from a local, which the assignment moves in, and from a copy of another
        // struct's field, which that struct keeps.
        let source = """
            func main() {
                var e = Enemy(alive: true, stats: Stats(alive: true, hp: 100, speed: 3), armor: 5)
                e.stats = Stats(alive: false, hp: 50, speed: 1)
                print(e.stats.hp)
                print(e.stats.speed)
                print(e.stats.alive)
                print(e.armor)
                let fresh = Stats(alive: true, hp: 7, speed: 8)
                e.stats = fresh
                print(e.stats.hp + e.stats.speed)
                print(e.alive)
                let other = Enemy(alive: false, stats: Stats(alive: false, hp: 20, speed: 2), armor: 1)
                e.stats = copy other.stats
                print(e.stats.hp)
                print(other.stats.hp)
            }
            """ + enemyAndStats
        let output = "50\n1\nfalse\n5\n15\ntrue\n20\n20\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: output, errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `a compound assignment to a field changes it in place, as a loop's condition reads it, in debug and release`(
        mode: [String],
    ) {
        let source = """
            func main() {
                var e = Enemy(alive: true, stats: Stats(alive: true, hp: 100, speed: 3), armor: 5)
                while e.stats.hp > 0 {
                    e.stats.hp -= 40 - e.armor
                    print(e.stats.hp)
                }
                e.stats.speed *= 4
                print(e.stats.speed)
                print(e.armor)
            }
            """ + enemyAndStats
        let output = "65\n30\n-5\n12\n5\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: output, errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]], [
        ("l.armor = 1", "4:5: error[E0251]: 'l' is a 'let', so its fields can't change"),
        ("l.stats.hp = 1", "4:5: error[E0251]: 'l' is a 'let', so its fields can't change"),
        ("e.alive = false", "4:7: error[E0252]: 'alive' is a 'let' field, so it can't change"),
        ("e.stats.alive = false", "4:13: error[E0252]: 'alive' is a 'let' field, so it can't change"),
        ("e.armor = true", "4:15: error[E0213]: expected Int, found Bool"),
        ("e.stats = l", "4:15: error[E0213]: expected Stats, found Enemy"),
        ("e.stats.hp += true", "4:5: error[E0215]: '+=' needs Int operands, found Int and Bool"),
        ("e.mana = 1", "4:7: error[E0244]: Enemy has no field 'mana'"),
        ("e.armor.hp = 1", "4:13: error[E0244]: Int has no field 'hp'"),
        ("hit(e).armor = 1", "4:5: error[E0223]: only a local, or a field of one, can be assigned"),
        (
            "var b = Boss(stats: Stats(alive: true, hp: 1, speed: 2), armor: 3)\n    b.stats.hp = 1",
            "5:7: error[E0252]: 'stats' is a 'let' field, so it can't change",
        ),
    ])
    func `a field of a 'let' or a temporary, a 'let' field, no field, or a wrong value is rejected in either build`(
        mode: [String], failure: (body: String, error: String),
    ) {
        let source = """
            func main() {
                let l = Enemy(alive: true, stats: Stats(alive: true, hp: 100, speed: 3), armor: 5)
                var e = Enemy(alive: true, stats: Stats(alive: true, hp: 100, speed: 3), armor: 5)
                \(failure.body)
                print(l.armor + e.armor)
            }
            func hit(_ e: Enemy) -> Enemy { copy e }
            """ + enemyAndStats
        let expected = CommandResult(exitCode: 1, output: "", errors: "main.rayo:\(failure.error)\n")
        #expect(run(source, options: mode) == expected)
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `assigning a field of a borrowed parameter is an error that names the parameter, in debug and release`(
        mode: [String],
    ) {
        let source = """
            func main() {}
            func heal(_ e: Enemy) {
                e.stats.hp = 100
            }
            """ + enemyAndStats
        let errors = "main.rayo:3:5: error[E0230]: 'e' is a borrowed parameter, so it can't change\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 1, output: "", errors: errors))
    }

    @Test(arguments: [["--debug"], ["--release"]], [
        ("var e: Enemy\n    e.armor = 1\n    print(e.armor)", "3:5: error[E0304]: 'e' isn't initialized"),
        ("var e = enemy()\n    _ = e\n    e.stats.hp = 1\n    print(e.armor)", "4:5: error[E0302]: 'e' was moved"),
        (
            "var e = enemy()\n    print(e.armor)\n    e.armor = 1",
            "4:5: error[E0308]: the value assigned to 'e.armor' is never read",
        ),
        (
            "var e = enemy()\n    e.stats.hp = 1\n    print(e.armor)",
            "3:5: error[E0308]: the value assigned to 'e.stats.hp' is never read",
        ),
        (
            "var e = enemy()\n    e.stats.hp = 1\n    e.stats.hp = 2\n    _ = e",
            "3:5: error[E0308]: the value assigned to 'e.stats.hp' is never read",
        ),
    ])
    func `a field is assigned only in a local that holds a value, and only where some code reads it, in both builds`(
        mode: [String], failure: (body: String, error: String),
    ) {
        let source = """
            func main() {
                \(failure.body)
            }
            func enemy() -> Enemy { Enemy(alive: true, stats: Stats(alive: true, hp: 100, speed: 3), armor: 5) }
            """ + enemyAndStats
        let expected = CommandResult(exitCode: 1, output: "", errors: "main.rayo:\(failure.error)\n")
        #expect(run(source, options: mode) == expected)
    }
}
