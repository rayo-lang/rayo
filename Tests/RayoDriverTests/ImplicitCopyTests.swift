import Testing
import RayoDriver

struct ImplicitCopyTests {
    // An initializer's arguments and an array literal's elements take an Int, a UInt or a Bool from a local that is
    // used, and changed, after them, and a `return` takes an Int from a borrowed parameter's field, which it can't
    // move out of.
    @Test(arguments: [["--debug"], ["--release"]])
    func `an Int, UInt or Bool place passed on is copied, and stays usable, in debug and in release`(mode: [String]) {
        let source = """
            func main() {
                var hp = 5
                var level: UInt = 2
                var alive = true
                let e = Enemy(hp: hp, level: level, alive: alive)
                let hps: [2 of Int] = [hp, hp]
                hp = hp + 1
                level = level + 1
                alive = !alive
                print(hp)
                print(level)
                print(alive)
                print(e.hp + hps[0] + hps[1])
                print(e.level)
                print(e.alive)
                print(hpOf(e))
            }
            func hpOf(_ e: Enemy) -> Int {
                return e.hp
            }
            struct Enemy(var hp: Int, var level: UInt, var alive: Bool)
            """
        #expect(run(source, options: mode) == CommandResult(
            exitCode: 0, output: "6\n3\nfalse\n15\n2\ntrue\n5\n", errors: "",
        ))
    }

    // A `let`, a `var` and an assignment take an Int, a UInt or a Bool from a place that is used, and changed, after
    // them, and from a borrowed parameter's field.
    @Test(arguments: [["--debug"], ["--release"]])
    func `an Int, UInt or Bool place given to a 'let', a 'var' or an assignment is copied`(mode: [String]) {
        let source = """
            func main() {
                var p = 5
                let q = p
                var r: UInt = 2
                var s = r
                var alive = true
                var t = false
                print(t)
                t = alive
                p = p + 1
                r = r + 1
                alive = false
                s = s + 10
                print(p + q)
                print(r + s)
                print(t)
                print(alive)
                print(hpOf(Stats(hp: 7)))
            }
            func hpOf(_ s: Stats) -> Int {
                let hp = s.hp
                return hp
            }
            struct Stats(var hp: Int)
            """
        #expect(run(source, options: mode) == CommandResult(
            exitCode: 0, output: "false\n11\n15\ntrue\nfalse\n7\n", errors: "",
        ))
    }
}
