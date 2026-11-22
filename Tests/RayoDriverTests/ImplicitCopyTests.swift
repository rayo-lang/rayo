import Testing
import RayoDriver

struct ImplicitCopyTests {
    // An initializer's arguments, an array literal's elements and a `return` take an Int, a UInt or a Bool from a
    // place that is used, and changed, after them.
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
}
