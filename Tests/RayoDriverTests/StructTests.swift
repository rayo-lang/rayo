import Testing
import RayoDriver

struct StructTests {
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
                print(damage(to: &e, by: 12))
                print(e.hp - damage(to: &e, by: 30))
                if e.alive && e.hp > e.armor { print(-e.armor) }
                print(spawned(hp: 40).hp)
                let nothing = Empty()
                _ = consume nothing
            }
            func damage(to e: &Enemy, by hit: Int) -> Int { return hit - e.armor }
            func spawned(hp: Int) -> Enemy { Enemy(alive: false, hp: copy hp, armor: 0) }
            struct Enemy(let alive: Bool, var hp: Int, let armor: Int)
            struct Empty
            """
        #expect(run(source, options: mode) == CommandResult(exitCode: 0, output: "100\n5\n7\n75\n-5\n40\n", errors: ""))
    }
}
