import Testing
import RayoDiagnostics

/// A struct with a field of each kind the tests drop: an implicitly copyable one and an array.
private let enemy = "struct Enemy(var hp: Int, var slots: [2 of Int])"

struct UnusedValueTests {
    @Test func `a parameter that owns its argument, which no code reads, is reported where it is declared`() {
        let source = "func main() {\n    show(1, 2)\n}\nfunc show(_ n: Int, _ m: Int) {\n    print(m)\n}"
        #expect(diagnostics(source).map(\.description) == [
            "4:13: error[E0318]: the parameter 'n' is never read; write '_ = consume n' to drop it",
        ])
    }

    @Test(arguments: [("func f(_ e: Enemy) {}", "e"), ("func f(_ a: [2 of Int]) {}", "a")])
    func `a parameter that owns a struct or an array, which no code reads, is reported where it is declared`(
        function: String, name: String,
    ) {
        let source = "func main() {}\n\(function)\n\(enemy)"
        #expect(diagnostics(source).map(\.description) == [
            "2:10: error[E0318]: the parameter '\(name)' is never read; write '_ = consume \(name)' to drop it",
        ])
    }

    // A parameter that borrows its argument holds a value its caller owns, so nothing is lost when no code reads it.
    @Test(arguments: [
        ("func show(_ n: Int) {\n    _ = n\n}", "show(1)"), ("func show(_ n: Int) {\n    _ = consume n\n}", "show(1)"),
        ("func show(_ e: Enemy) {\n    _ = consume e\n}", "show(Enemy(hp: 1, slots: [2, 3]))"),
        ("func show(_ n: &Int) {}", "let a = 1\n    show(&a)"),
    ])
    func `a parameter dropped with '_ =', or one that borrows its argument, needs no read`(
        function: String, call: String,
    ) {
        #expect(errors("func main() {\n    \(call)\n}\n\(function)\n\(enemy)") == [])
    }

    // `_ = consume` moves the value out of its place and drops it, so the place holds no value after it. `_ = copy`
    // drops a copy, and leaves the place as it was.
    @Test(arguments: [
        ("let boss = Enemy(hp: 1, slots: [2, 3])\n    _ = consume boss\n    print(boss.hp)",
         [ErrorCode.usedAfterMove(name: "boss")]),
        ("let boss = Enemy(hp: 1, slots: [2, 3])\n    _ = copy boss\n    print(boss.hp)", []),
        ("let boss = Enemy(hp: 1, slots: [2, 3])\n    _ = consume boss.slots\n    _ = copy boss",
         [.usedPartlyMoved(name: "boss", field: "boss.slots")]),
        ("let grid = [4, 5]\n    _ = consume grid\n    print(grid[0])", [.usedAfterMove(name: "grid")]),
        ("let grid = [4, 5]\n    _ = copy grid\n    print(grid[0])", []),
    ])
    func `a struct or an array dropped with '_ = consume' is moved, and one dropped with '_ = copy' stays whole`(
        statements: String, expected: [ErrorCode],
    ) {
        #expect(errors("func main() {\n    \(statements)\n}\n\(enemy)") == expected)
    }
}
