import Testing
import RayoDiagnostics

struct MoveTests {
    @Test func `a move out of a borrowed parameter waits to be reported until the program checks`() {
        let source = "func main() {}\nfunc f(x: Int) {\n    let y = x\n    let z: Bool = 1\n}"
        #expect(diagnostics(source).map(\.code) == [.typeMismatch(expected: "Bool", found: "Int")])
    }

    @Test func `a move out of a borrowed parameter, or out of a field of one, names the parameter and the field`() {
        let source = """
            func main() {}
            func f(n: Int, s: Stats) {
                let m = n
                let hp = s.hp
                print(m + hp)
            }
            struct Stats(var hp: Int)
            """
        #expect(diagnostics(source).map(\.description) == [
            "3:13: error[E0301]: can't move the borrowed parameter 'n'; write 'copy' before it to take a copy",
            "4:14: error[E0311]: can't move 's.hp' out of the borrowed parameter 's'; write 'copy' before it to take a "
                + "copy",
        ])
    }

    // The local or parameter that was copied keeps the field.
    @Test(arguments: [
        "func f() -> Int {\n    let e = E(a: S(n: 1))\n    let s = (copy e).a\n    return e.a.n + s.n\n}",
        "func f(e: E) -> S { (copy e).a }",
    ])
    func `a field taken from a copy moves out of the copy`(function: String) {
        let source = "func main() {}\n\(function)\nstruct E(var a: S)\nstruct S(var n: Int)"
        #expect(errors(source) == [])
    }

    // An index a local holds is known only when the program runs, so the error names an element by its array, as it
    // does an element at an index the source writes.
    @Test(arguments: [
        ("let before = wave.enemies[i]\n    print(before.stats.hp)",
         "4:18: error[E0315]: can't move an element out of 'wave.enemies'; write 'copy' before it to take a copy"),
        ("let stats = wave.enemies[i].stats\n    print(stats.hp)",
         "4:17: error[E0315]: can't move 'stats' out of an element of 'wave.enemies'; write 'copy' before it to take "
            + "a copy"),
        ("let hp = wave.enemies[i].stats.hp\n    print(hp)",
         "4:14: error[E0315]: can't move 'stats.hp' out of an element of 'wave.enemies'; write 'copy' before it to "
            + "take a copy"),
        ("let first = wave.enemies[0]\n    print(first.stats.hp)",
         "4:17: error[E0315]: can't move an element out of 'wave.enemies'; write 'copy' before it to take a copy"),
    ])
    func `a move out of an element names the array it lies in, and the part of the element it takes`(
        statements: String, message: String,
    ) {
        let source = """
            func main() {
                let wave = Wave(enemies: [Enemy(stats: Stats(hp: 1)), Enemy(stats: Stats(hp: 2))])
                let i: UInt = 1
                \(statements)
            }
            struct Wave(var enemies: [2 of Enemy])
            struct Enemy(var stats: Stats)
            struct Stats(var hp: Int)
            """
        #expect(diagnostics(source).map(\.description) == [message])
    }

    // A `copy` is a value, not a place. As with any temporary, its elements can't be moved out of it; `copy a[0]`
    // copies the element instead. The source gives the copy no name, so the error names it as an array.
    @Test func `an element taken from a copy can't be moved out of the copy`() {
        let source = "func main() {}\nfunc f(a: [2 of S]) -> S { (copy a)[0] }\nstruct S(var n: Int)"
        #expect(diagnostics(source).map(\.description) == [
            "2:28: error[E0315]: can't move an element out of an array; write 'copy' before it to take a copy",
        ])
    }
}
