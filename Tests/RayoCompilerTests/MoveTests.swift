import Testing
import RayoDiagnostics

struct MoveTests {
    @Test func `a move out of a borrowed parameter waits to be reported until the program checks`() {
        let source = "func main() {}\nfunc f(x: &Int) {\n    let y = consume x\n    let z: Bool = 1\n}"
        #expect(diagnostics(source).map(\.code) == [.typeMismatch(expected: "Bool", found: "Int")])
    }

    @Test func `a move out of a borrowed parameter, or out of a field of one, names the parameter and the field`() {
        let source = """
            func main() {}
            func f(n: &Int, s: &Stats) {
                let m = consume n
                let hp = consume s.hp
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
        "func f(e: &E) -> S { (copy e).a }",
    ])
    func `a field taken from a copy moves out of the copy`(function: String) {
        let source = "func main() {}\n\(function)\nstruct E(var a: S)\nstruct S(var n: Int)"
        #expect(errors(source) == [])
    }

    // An index a local holds is known only when the program runs, so the error names an element by its array, as it
    // does an element at an index the source writes.
    @Test(arguments: [
        ("let before = consume wave.enemies[i]\n    print(before.stats.hp)",
         "4:18: error[E0315]: can't move an element out of 'wave.enemies'; write 'copy' before it to take a copy"),
        ("let stats = consume wave.enemies[i].stats\n    print(stats.hp)",
         "4:17: error[E0315]: can't move 'stats' out of an element of 'wave.enemies'; write 'copy' before it to take "
            + "a copy"),
        ("let hp = consume wave.enemies[i].stats.hp\n    print(hp)",
         "4:14: error[E0315]: can't move 'stats.hp' out of an element of 'wave.enemies'; write 'copy' before it to "
            + "take a copy"),
        ("let first = consume wave.enemies[0]\n    print(first.stats.hp)",
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

    // The array named is the innermost one the source can name: the source names an array up to the first index a
    // local holds. A part inside that element that the source can't write from it, such as an element of it or a part
    // a later such index leads to, is called a part.
    @Test(arguments: [
        ("let x = consume w.items[i].inner[j].n", "a part out of an element of 'w.items'"),
        ("let x = consume w.items[i].inner[0].n", "'inner[0].n' out of an element of 'w.items'"),
        ("let c = consume w.items[i].inner[0]\n    let x = consume c.n", "'inner[0]' out of an element of 'w.items'"),
        ("let x = consume w.items[0].inner[i].n", "'n' out of an element of 'w.items[0].inner'"),
        ("let x = consume g[i][j]", "a part out of an element of 'g'"),
        ("let x = consume g[i][0]", "a part out of an element of 'g'"),
        ("let x = consume g[0][i]", "an element out of 'g[0]'"),
        ("let x = consume g[0][1]", "an element out of 'g[0]'"),
    ])
    func `a move out of an element inside another names the innermost array the source names`(
        statements: String, part: String,
    ) {
        let source = """
            func main() {
                let w = W(items: [B(inner: [C(n: 1), C(n: 2)]), B(inner: [C(n: 3), C(n: 4)])])
                let g: [2 of [2 of Int]] = [[1, 2], [3, 4]]
                let i: UInt = 1
                let j: UInt = 0
                \(statements)
                print(x + g[0][0] + w.items[0].inner[0].n + Int(copy i) + Int(copy j))
            }
            struct W(var items: [2 of B])
            struct B(var inner: [2 of C])
            struct C(var n: Int)
            """
        #expect(diagnostics(source).map(\.description) == [
            "6:13: error[E0315]: can't move \(part); write 'copy' before it to take a copy",
        ])
    }

    @Test func `'consume' moves the place out, so a later use of it is reported as a use after a move`() {
        let source = """
            func main() {
                let e = Enemy(stats: Stats(hp: 1))
                let s = consume e.stats
                print(s.hp)
                print(e.stats.hp)
            }
            struct Enemy(var stats: Stats)
            struct Stats(var hp: Int)
            """
        let found = diagnostics(source)
        #expect(found.map(\.description) == ["5:11: error[E0302]: 'e.stats' was moved"])
        #expect(found.flatMap(\.notes) == ["3:13: note: moved here"])
    }

    // A `consume` moves as any other move does, so it can't take what a borrowed parameter or an array holds.
    @Test func `'consume' of a borrowed parameter or of an element is reported as any such move is`() {
        let source = "func main() {}\nfunc f(n: &Int, a: &[2 of Int]) -> Int {\n    consume n + consume a[0]\n}"
        #expect(diagnostics(source).map(\.description) == [
            "3:5: error[E0301]: can't move the borrowed parameter 'n'; write 'copy' before it to take a copy",
            "3:17: error[E0315]: can't move an element out of 'a'; write 'copy' before it to take a copy",
        ])
    }

    @Test func `a place moved into a parameter that owns it can't be used after the call`() {
        let source = """
            func main() {
                let boss = Enemy(stats: Stats(hp: 1))
                keep(consume boss)
                print(boss.stats.hp)
            }
            func keep(_ e: Enemy) { print(e.stats.hp) }
            struct Enemy(var stats: Stats)
            struct Stats(var hp: Int)
            """
        let found = diagnostics(source)
        #expect(found.map(\.description) == ["4:11: error[E0302]: 'boss' was moved"])
        #expect(found.flatMap(\.notes) == ["3:10: note: moved here"])
    }

    @Test func `a field moved out of a parameter that owns it leaves the parameter unusable as a whole`() {
        let source = """
            func main() {}
            func f(_ x: Enemy) -> Stats {
                let s = consume x.stats
                keep(consume x)
                return consume s
            }
            func keep(_ e: Enemy) { print(e.stats.hp) }
            struct Enemy(var stats: Stats)
            struct Stats(var hp: Int)
            """
        let found = diagnostics(source)
        #expect(found.map(\.description) == [
            "4:10: error[E0309]: 'x.stats' was moved out of 'x', so 'x' can't be used as a whole",
        ])
        #expect(found.flatMap(\.notes) == ["3:13: note: moved here"])
    }

    // A `copy` is a value, not a place. As with any temporary, its elements can't be moved out of it; `copy a[0]`
    // copies the element instead. The source gives the copy no name, so the error names it as an array.
    @Test func `an element taken from a copy can't be moved out of the copy`() {
        let source = "func main() {}\nfunc f(a: &[2 of S]) -> S { (copy a)[0] }\nstruct S(var n: Int)"
        #expect(diagnostics(source).map(\.description) == [
            "2:29: error[E0315]: can't move an element out of an array; write 'copy' before it to take a copy",
        ])
    }
}
