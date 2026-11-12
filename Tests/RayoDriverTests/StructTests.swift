import Testing
import RayoDriver

struct StructTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `a struct's name is a type, which locals, parameters and results may have, in debug and in release`(
        mode: [String],
    ) {
        let source = """
            func main() {
                var shot: Shot
                print(1)
            }
            func relay(_ s: Shot) -> Shot { kept(s) }
            func kept(_ s: Shot) -> Shot {
                var k: Shot
                k = copy s
                let t = k
                return t
            }
            struct Shot(var hit: Hit, let team: Bool)
            struct Hit(var damage: Int)
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "1\n", errors: ""))
    }

    @Test func `a local may share a struct's name, which a type names the struct by, and any other use the local`() {
        let body = "let S = 2\nvar s: S\nprint(S)"
        #expect(run("func main() {\n\(body)\n}\nstruct S(var a: Int)") ==
            CommandResult(exitCode: 0, output: "2\n", errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `a struct made by its initializer holds its fields, which borrows read, in debug and in release`(
        mode: [String],
    ) {
        // `Enemy` lays `alive` out after the Ints, so each field is read from where its layout puts it. Each read
        // leaves `e` whole, so it is passed and read again after. `nothing` is bound before it is discarded, so a
        // struct with no fields is stored in a local's slot, which discarding the call alone would skip.
        let source = """
            func main() {
                let hp = 100
                let e = Enemy(alive: true, hp: hp, armor: 5)
                print(e.hp)
                print(e.armor)
                print(damage(to: e, by: 12))
                print(e.hp - damage(to: e, by: 30))
                if e.alive && e.hp > e.armor { print(-e.armor) }
                print(spawned(hp: 40).hp)
                let nothing = Empty()
                _ = nothing
            }
            func damage(to e: Enemy, by hit: Int) -> Int { return hit - e.armor }
            func spawned(hp: Int) -> Enemy { Enemy(alive: false, hp: copy hp, armor: 0) }
            struct Enemy(let alive: Bool, var hp: Int, let armor: Int)
            struct Empty
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "100\n5\n7\n75\n-5\n40\n", errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]], [
        ("let e = Enemy(hp: 100)", "2:13: error[E0245]: the call leaves out the field 'armor'"),
        ("let e = Enemy(hp: 100, armor: 5, speed: 3)", "2:38: error[E0244]: Enemy has no field 'speed'"),
        ("let e = Enemy(hp: 1, hp: 2, armor: 5)", "2:26: error[E0246]: the call gives the field 'hp' more than once"),
        (
            "let e = Enemy(hp: 100, armr: 5)",
            "2:28: error[E0228]: expected 'armor:' before the argument, found 'armr:'",
        ),
        (
            "let e = Enemy(armor: 5, hp: 100)",
            "2:29: error[E0247]: 'hp' must come before 'armor', as the struct declares them",
        ),
        ("let e = Enemy(hp: true, armor: 5)", "2:23: error[E0248]: the field 'hp' takes Int, found Bool"),
        ("let e = Enemy(hp: 100, armor: 5)\n    print(e.speed)", "3:13: error[E0244]: Enemy has no field 'speed'"),
        ("let hp = 100\n    let e = Enemy(hp: hp, armor: 5)\n    print(hp)", "4:11: error[E0302]: 'hp' was moved"),
    ])
    func `a call that doesn't give each field once, in order, or a read of no field, is an error, in debug and release`(
        mode: [String], failure: (body: String, error: String),
    ) {
        let source = "func main() {\n    \(failure.body)\n}\nstruct Enemy(var hp: Int, let armor: Int)"
        let expected = CommandResult(exitCode: 1, output: "", errors: "main.rayo:\(failure.error)\n")
        #expect(run(source, options: mode) == expected)
    }
}

/// A struct that holds a struct that holds a struct. `Stats` lays `alive` out after its Ints, and `Boss` lays `alive`
/// out after `minion`, so a read that steps into the wrong element at any level reads another field.
private let bossEnemyAndStats = """

    struct Boss(let alive: Bool, var minion: Enemy)
    struct Enemy(var stats: Stats, let armor: Int)
    struct Stats(let alive: Bool, var hp: Int, var speed: Int)
    """

struct NestedStructTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `a field read through the fields that hold it gives the value it was made with, in debug and in release`(
        mode: [String],
    ) {
        // `e` is made from a nested initializer call, and `b` holds an Enemy made from the local `stats`, which that
        // call moves in. Each read leaves its struct whole, so it is read again after.
        let source = """
            func main() {
                let e = Enemy(stats: Stats(alive: true, hp: 100, speed: 3), armor: 5)
                print(e.stats.hp)
                print(e.stats.speed)
                print(e.stats.alive)
                print(e.armor - e.stats.speed)
                let stats = Stats(alive: false, hp: 40, speed: 7)
                let b = Boss(alive: true, minion: Enemy(stats: stats, armor: 9))
                print(b.minion.stats.hp)
                print(b.minion.stats.speed)
                print(b.minion.stats.alive)
                print(b.minion.armor)
                print(b.alive)
            }
            """ + bossEnemyAndStats
        let output = "100\n3\ntrue\n2\n40\n7\nfalse\n9\ntrue\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: output, errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `a field read through the fields of a borrowed parameter decides the result, in debug and in release`(
        mode: [String],
    ) {
        let source = """
            func main() {
                let e = Enemy(stats: Stats(alive: true, hp: 100, speed: 3), armor: 5)
                print(left(in: e, after: 30))
                print(left(in: e, after: 200))
                let b = Boss(alive: true, minion: Enemy(stats: Stats(alive: true, hp: 1, speed: 8), armor: 2))
                print(reach(of: b))
            }
            func left(in e: Enemy, after hit: Int) -> Int {
                if hit >= e.stats.hp + e.armor { return 0 }
                return e.stats.hp + e.armor - hit
            }
            func reach(of b: Boss) -> Int { b.minion.stats.speed * b.minion.armor }
            """ + bossEnemyAndStats
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "75\n0\n16\n", errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]], [
        ("print(e.stats.mana)", "4:19: error[E0244]: Stats has no field 'mana'"),
        ("print(b.minion.stats.mana)", "4:26: error[E0244]: Stats has no field 'mana'"),
        ("print(b.minion.mana)", "4:20: error[E0244]: Enemy has no field 'mana'"),
        ("let f = Enemy(stats: e, armor: 1)", "4:26: error[E0248]: the field 'stats' takes Stats, found Enemy"),
        (
            "let f = Enemy(stats: e.stats, armor: 1)",
            "4:26: error[E0250]: moving a field out of a struct isn't supported",
        ),
        (
            "let s = Stats(alive: true, hp: 1, speed: 2)\n    let f = Enemy(stats: s, armor: 1)\n    print(s.hp)",
            "6:11: error[E0302]: 's' was moved",
        ),
    ])
    func `a nested read of no field, a field given a wrong or taken value, or a moved local is an error in both builds`(
        mode: [String], failure: (body: String, error: String),
    ) {
        let source = """
            func main() {
                let e = Enemy(stats: Stats(alive: true, hp: 100, speed: 3), armor: 5)
                let b = Boss(alive: true, minion: Enemy(stats: Stats(alive: true, hp: 1, speed: 8), armor: 2))
                \(failure.body)
            }
            """ + bossEnemyAndStats
        let expected = CommandResult(exitCode: 1, output: "", errors: "main.rayo:\(failure.error)\n")
        #expect(run(source, options: mode) == expected)
    }
}

struct FieldCopyTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `a copy of a field is a value of its own, and leaves its struct whole, in debug and in release`(
        mode: [String],
    ) {
        // Each copy starts with the field's value, and changing the copy leaves the field as it was. `e` is read,
        // copied and passed after the copies are made, and moved last.
        let source = """
            func main() {
                let e = Enemy(stats: Stats(alive: true, hp: 100, speed: 3), armor: 5)
                var hp = copy e.stats.hp
                var stats = copy e.stats
                let armor = copy e.armor
                hp -= 30
                print(hp)
                print(stats.speed)
                stats = Stats(alive: false, hp: 1, speed: 9)
                print(stats.speed)
                print(armor)
                print(e.stats.hp)
                print(e.stats.speed)
                let kept = copy e
                print(kept.stats.alive)
                print(total(of: e))
                let last = e
                print(last.armor)
            }
            func total(of e: Enemy) -> Int { e.stats.hp + e.armor }
            """ + bossEnemyAndStats
        let output = "70\n3\n9\n5\n100\n3\ntrue\n105\n5\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: output, errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `assigning a field of a copy leaves the original's field as it was, and the other way round, in both builds`(
        mode: [String],
    ) {
        // The copies are of a field, of a whole struct, of a field that is itself a struct holding one, and of a field
        // of a borrowed parameter. Each is printed after both it and its original have been assigned, so a copy that
        // shared its original's storage would print the other's value.
        let source = """
            func main() {
                var e = Enemy(stats: Stats(alive: true, hp: 100, speed: 3), armor: 5)
                var stats = copy e.stats
                stats.hp = 1
                stats.speed += 4
                var kept = copy e
                kept.stats.hp = 2
                e.stats.hp = 50
                print(stats.hp)
                print(stats.speed)
                print(kept.stats.hp)
                print(kept.stats.speed)
                print(e.stats.hp)
                print(e.stats.speed)
                var b = Boss(alive: true, minion: Enemy(stats: Stats(alive: true, hp: 30, speed: 6), armor: 2))
                var minion = copy b.minion
                minion.stats.hp = 9
                b.minion.stats.speed = 8
                print(minion.stats.hp)
                print(minion.stats.speed)
                print(b.minion.stats.hp)
                print(b.minion.stats.speed)
                print(weakened(e).hp)
                print(e.stats.hp)
            }
            func weakened(_ e: Enemy) -> Stats {
                var s = copy e.stats
                s.hp -= 45
                return s
            }
            """ + bossEnemyAndStats
        let output = "1\n7\n2\n3\n50\n3\n9\n6\n30\n8\n5\n50\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: output, errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `a function returns a copy of a field of what it borrows, in debug and in release`(mode: [String]) {
        let source = """
            func main() {
                let e = Enemy(stats: Stats(alive: false, hp: 40, speed: 7), armor: 9)
                print(armorOf(e))
                print(statsOf(e).speed)
                print(statsOf(e).alive)
                print(hpOf(e))
            }
            func armorOf(_ e: Enemy) -> Int { return copy e.armor }
            func statsOf(_ e: Enemy) -> Stats { return copy e.stats }
            func hpOf(_ e: Enemy) -> Int { copy e.stats.hp }
            """ + bossEnemyAndStats
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "9\n7\nfalse\n40\n", errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]], [
        ("let h = copy e.mana", "4:20: error[E0244]: Enemy has no field 'mana'"),
        ("let h = copy e.stats.mana", "4:26: error[E0244]: Stats has no field 'mana'"),
    ])
    func `a copy of a field the struct doesn't have is an error that names the field, in debug and in release`(
        mode: [String], failure: (body: String, error: String),
    ) {
        let source = """
            func main() {
                let e = Enemy(stats: Stats(alive: true, hp: 100, speed: 3), armor: 5)
                print(e.armor)
                \(failure.body)
            }
            """ + bossEnemyAndStats
        let expected = CommandResult(exitCode: 1, output: "", errors: "main.rayo:\(failure.error)\n")
        #expect(run(source, options: mode) == expected)
    }
}
