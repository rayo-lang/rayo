import Testing
import RayoDriver

/// A struct that holds a struct. `Enemy` and `Stats` each lay `alive` out after its Ints, so an assignment that stores
/// into the wrong element at either level changes another field.
private let enemyAndStats = """

    struct Enemy(let alive: Bool, var stats: Stats, var armor: Int)
    struct Stats(let alive: Bool, var hp: Int, var speed: Int)
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
}
