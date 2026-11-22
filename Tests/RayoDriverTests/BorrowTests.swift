import Testing
import RayoDriver

struct BorrowTests {
    // The place changes once the `ref let`s that borrow it are last used, and a parameter's part is borrowed in place.
    @Test(arguments: [["--debug"], ["--release"]])
    func `a 'ref let' borrows its place, so the place keeps its value, in debug and in release`(mode: [String]) {
        let source = """
            func main() {
                var e = Enemy(stats: Stats(hp: 5), slots: [6, 7])
                ref let hp = e.stats.hp
                ref let slot = e.slots[1]
                let c = true
                ref let either = if c { e.slots[0] } else { hp }
                print(hp + slot + either)
                e.stats.hp = 1
                print(e.stats.hp + e.slots[1])
                print(stats(of: e))
            }
            func stats(of e: Enemy) -> Int {
                ref let s = e.stats
                return s.hp * 10
            }
            struct Enemy(var stats: Stats, var slots: [2 of Int])
            struct Stats(var hp: Int)
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "18\n8\n10\n", errors: ""))
    }

    // One branch borrows through another `ref let`, and the other gives a value, so the paths join holding different
    // borrows.
    @Test(arguments: [["--debug"], ["--release"]])
    func `a 'ref let' of an 'if' that borrows through another 'ref let' on one path runs`(mode: [String]) {
        let source = """
            func main() {
                var e = Enemy(stats: Stats(hp: 5))
                let c = false
                ref let st = e.stats
                ref let deep = if c { st.hp } else { 4 }
                ref let other = if !c { st.hp } else { 4 }
                print(deep + other)
                e.stats.hp = 2
                print(e.stats.hp)
            }
            struct Enemy(var stats: Stats)
            struct Stats(var hp: Int)
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "9\n2\n", errors: ""))
    }
}
