import Testing
import RayoDriver

struct MutableParameterTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `a 'mutable &Int' parameter changes its caller's local, in debug and in release`(mode: [String]) {
        let source = """
            func main() {
                var x = 1
                bump(mutable x)
                print(x)
            }
            func bump(_ n: mutable &Int) { n += 1 }
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "2\n", errors: ""))
    }

    @Test(arguments: [["--debug"], ["--release"]])
    func `a 'mutable &T' parameter changes its caller's UInt, Bool and array, and an owned parameter`(mode: [String]) {
        let source = """
            func main() {
                var u: UInt = 1
                var b = false
                var s = [1, 2]
                bumpCount(mutable u)
                flip(mutable b)
                fill(mutable s)
                print(u)
                print(b)
                print(s[0] + s[1])
                print(twice(5))
            }
            func bumpCount(_ n: mutable &UInt) { n += 1 }
            func flip(_ b: mutable &Bool) { b = !b }
            func fill(_ s: mutable &[2 of Int]) {
                s[0] = 10
                s = [s[0], 20]
            }
            func twice(_ n: Int) -> Int {
                bump(mutable n)
                bump(mutable n)
                return n
            }
            func bump(_ n: mutable &Int) { n += 1 }
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "2\ntrue\n30\n7\n", errors: ""))
    }

    // The caller's struct changes through a field, through an element's field, and as a whole.
    @Test(arguments: [["--debug"], ["--release"]])
    func `a 'mutable &T' parameter changes its caller's struct in place, in debug and in release`(mode: [String]) {
        let source = """
            func main() {
                var boss = Enemy(stats: Stats(hp: 1), slots: [1, 2])
                var wave = Wave(enemies: [makeEnemy(3), makeEnemy(4)])
                let i: UInt = 1
                heal(mutable boss)
                print(boss.stats.hp)
                heal(mutable wave.enemies[i])
                print(wave.enemies[0].stats.hp)
                print(wave.enemies[1].stats.hp)
                respawn(mutable boss)
                print(boss.stats.hp)
                print(boss.slots[1])
            }
            struct Enemy(var stats: Stats, var slots: [2 of Int])
            struct Stats(var hp: Int)
            struct Wave(var enemies: [2 of Enemy])
            func makeEnemy(_ hp: Int) -> Enemy { Enemy(stats: Stats(hp: hp), slots: [0, 0]) }
            func heal(_ e: mutable &Enemy) { e.stats.hp = 100 }
            func respawn(_ e: mutable &Enemy) { e = Enemy(stats: Stats(hp: 7), slots: [8, 9]) }
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "100\n3\n100\n7\n9\n", errors: ""))
    }

    // The parameter is lent on for change with `mutable`, and shared bare, with `&`, to `print` and as a copy.
    @Test(arguments: [["--debug"], ["--release"]])
    func `a 'mutable &T' parameter is passed on as any place is, in debug and in release`(mode: [String]) {
        let source = """
            func main() {
                var boss = Enemy(stats: Stats(hp: 1), slots: [1, 2])
                relay(mutable boss)
                print(boss.stats.hp)
                print(boss.slots[0])
            }
            struct Enemy(var stats: Stats, var slots: [2 of Int])
            struct Stats(var hp: Int)
            func relay(_ e: mutable &Enemy) {
                heal(mutable e)
                bump(mutable e.stats.hp)
                bump(mutable e.slots[0])
                show(e)
                show(&e)
                print(e.slots[0])
                let copied = e.stats.hp
                print(copied)
            }
            func heal(_ e: mutable &Enemy) { e.stats.hp = 100 }
            func bump(_ n: mutable &Int) { n += 1 }
            func show(_ e: &Enemy) { print(e.stats.hp) }
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "101\n101\n2\n101\n101\n2\n",
                                                             errors: ""))
    }

    @Test func `'mutable' picks the overload that borrows for change, and a bare or '&' place the one that borrows`() {
        let source = """
            func main() {
                var a = 1
                show(a)
                show(&a)
                show(mutable a)
                show(a)
            }
            func show(_ n: &Int) { print(n + 10) }
            func show(_ n: mutable &Int) {
                print(n + 20)
                n = 5
            }
            """
        #expect(run(source) == CommandResult(exitCode: 0, output: "11\n11\n21\n15\n", errors: ""))
    }
}
