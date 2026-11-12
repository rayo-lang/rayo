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
        // leaves `e` whole, so it is passed and read again after. `Empty` holds no field, and a local holds it all
        // the same.
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
