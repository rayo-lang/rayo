import Testing
import RayoDriver

struct BorrowTests {
    // The place changes once the `let`s that borrow it are last used, and a parameter's part is borrowed in place.
    @Test("a 'let' of a place borrows it, so the place keeps its value, in debug and in release",
          arguments: [["--debug"], ["--release"]])
    func borrows(mode: [String]) {
        let source = """
            func main() {
                var e = Enemy(stats: Stats(hp: 5), slots: [6, 7])
                let hp = e.stats.hp
                let slot = e.slots[1]
                let c = true
                let either = if c { e.slots[0] } else { hp }
                print(hp + slot + either)
                e.stats.hp = 1
                print(e.stats.hp + e.slots[1])
                print(stats(of: e))
            }
            func stats(of e: Enemy) -> Int {
                let s = e.stats
                return s.hp * 10
            }
            struct Enemy(var stats: Stats, var slots: [2 of Int])
            struct Stats(var hp: Int)
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "18\n8\n10\n", errors: ""))
    }
}
