import Testing
import RayoDiagnostics

/// A struct with a field of each kind the tests drop: an implicitly copyable one and an array.
private let enemy = "struct Enemy(var hp: Int, var slots: [2 of Int])"

struct UnusedValueTests {
    @Test func `a parameter that owns its argument, which no code reads, is reported where it is declared`() {
        let source = "func main() {\n    show(1, 2)\n}\nfunc show(_ n: Int, _ m: Int) {\n    print(m)\n}"
        #expect(diagnostics(source).map(\.description) == [
            "4:13: error[E0318]: the parameter 'n' is never read; write '_ = n' to drop it",
        ])
    }

    // `_ =` drops a copy of an implicitly copyable value bare, and any other value only once `consume` moves it out.
    @Test(arguments: [
        ("func f(_ n: Int) {}", "'n'", "'_ = n'"), ("func f(_ u: UInt) {}", "'u'", "'_ = u'"),
        ("func f(_ b: Bool) {}", "'b'", "'_ = b'"), ("func f(_ e: Enemy) {}", "'e'", "'_ = consume e'"),
        ("func f(_ a: [2 of Int]) {}", "'a'", "'_ = consume a'"),
    ])
    func `an unread parameter that owns its argument names the drop that fits its type`(
        function: String, name: String, drop: String,
    ) {
        let source = "func main() {}\n\(function)\n\(enemy)"
        #expect(diagnostics(source).map(\.description) == [
            "2:10: error[E0318]: the parameter \(name) is never read; write \(drop) to drop it",
        ])
    }

    // The compiler can't tell which path a run takes, so a read on any path uses the parameter.
    @Test(arguments: [
        "func f(_ n: Int, _ c: Bool) {\n    if c { print(n) }\n}",
        "func f(_ e: Enemy, _ c: Bool) {\n    if c { _ = consume e }\n}",
        "func f(_ e: Enemy, _ c: Bool) {\n    while c {\n        _ = consume e.slots\n        return\n    }\n}",
    ])
    func `a parameter that one path reads and another doesn't is used`(function: String) {
        #expect(errors("func main() {}\n\(function)\n\(enemy)") == [])
    }

    @Test(arguments: [
        ("_ = consume item\n    print(item.hp)", [ErrorCode.usedAfterMove(name: "item")]),
        ("_ = consume item.slots\n    _ = copy item", [.usedPartlyMoved(name: "item", field: "item.slots")]),
        ("_ = consume item.slots\n    print(item.hp)", []),
    ])
    func `an owning parameter dropped with '_ = consume', whole or in part, is moved out as a local is`(
        statements: String, expected: [ErrorCode],
    ) {
        #expect(errors("func main() {}\nfunc adopt(_ item: Enemy) {\n    \(statements)\n}\n\(enemy)") == expected)
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
