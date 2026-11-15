import Testing
import RayoDriver

/// A struct that holds a struct, and a function that makes one. `Enemy` and `Stats` each lay `alive` out after its
/// Ints, so a move out of the wrong element at either level gives another field's value.
private let enemyAndStats = """

    func enemy() -> Enemy { Enemy(alive: true, stats: Stats(alive: true, hp: 100, speed: 3), armor: 5) }
    struct Enemy(let alive: Bool, var stats: Stats, var armor: Int)
    struct Stats(let alive: Bool, var hp: Int, var speed: Int)
    """

struct FieldMoveTests {
    @Test(arguments: [["--debug"], ["--release"]])
    func `a field moved out of a local holds its value, and the struct's other fields keep theirs, in both builds`(
        mode: [String],
    ) {
        // `e` is a `var`, whose other fields are copied, assigned and moved in turn, and `l` a `let`; `copied` moves out
        // of a copy of `l`, which keeps its own, `l`'s `hp` moves out of the struct inside it, `made`'s `stats` out of a
        // call's result, and `statsOf` returns a local's.
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
                let copied = (copy l).stats
                print(copied.hp)
                let hp = l.stats.hp
                print(hp)
                print(l.stats.speed)
                print(l.armor)
                let made = Enemy(alive: true, stats: enemy().stats, armor: 9)
                print(made.stats.hp)
                print(statsOf(Enemy(alive: true, stats: Stats(alive: true, hp: 1, speed: 4), armor: 2)).speed)
            }
            func statsOf(_ given: Enemy) -> Stats {
                let e = copy given
                return e.stats
            }
            """ + enemyAndStats
        let output = "100\n3\n5\ntrue\n6\n20\n20\n7\n2\n100\n4\n"
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: output, errors: ""))
    }
}
