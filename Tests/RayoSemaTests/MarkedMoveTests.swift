import Testing

/// The declarations the tests' functions use: a struct with a nested struct in it, a struct that holds an array, and a
/// function that makes an enemy.
private let declarations = """
    struct Enemy(var stats: Stats)
    struct Stats(var hp: Int)
    struct Board(var grid: [2 of Int])
    func makeEnemy() -> Enemy { Enemy(stats: Stats(hp: 1)) }
    """

/// The errors that `function`, beside an empty `main` and the declarations, reports, each as its position, code and
/// message.
private func messages(of function: String) -> [String] {
    diagnostics("func main() {}\n\(declarations)\n\(function)").map(\.description)
}

struct ReturnedPlaceTests {
    @Test(arguments: [
        ("func f() -> Enemy {\n    let b = makeEnemy()\n    return b\n}", "8:12", "an Enemy", "b"),
        ("func f() -> [2 of Int] {\n    var b = [1, 2]\n    return b\n}", "8:12", "a [2 of Int]", "b"),
        ("func f(_ b: Enemy) -> Enemy { b }", "6:31", "an Enemy", "b"),
        ("func f(_ b: Enemy) { b }", "6:22", "an Enemy", "b"),
        ("func f(_ b: Enemy) -> Stats { b.stats }", "6:31", "a Stats", "b.stats"),
    ])
    func `a place returned bare names 'consume' and 'copy'`(
        function: String, position: String, type: String, place: String,
    ) {
        #expect(messages(of: function) == [
            "\(position): error[E0297]: the function returns \(type); write 'consume \(place)' or 'copy \(place)'",
        ])
    }

    @Test(arguments: [
        ("func f(_ a: &Enemy) -> Enemy {\n    return a\n}", "7:12", "an Enemy", "a"),
        ("func f(_ a: &[2 of Int]) -> [2 of Int] { a }", "6:42", "a [2 of Int]", "a"),
        ("func f(_ g: &[2 of Enemy]) -> Enemy { g[0] }", "6:39", "an Enemy", "g[0]"),
    ])
    func `a place the code can't move out of, returned bare, names 'copy' alone`(
        function: String, position: String, type: String, place: String,
    ) {
        #expect(messages(of: function) == [
            "\(position): error[E0297]: the function returns \(type); write 'copy \(place)'",
        ])
    }

    @Test(arguments: [
        "func f() -> Enemy {\n    let b = makeEnemy()\n    return consume b\n}",
        "func f(_ a: &Enemy) -> Enemy {\n    return copy a\n}",
        "func f(_ b: Enemy) -> Stats { consume b.stats }",
        "func f() -> Int {\n    let n = 1\n    return n\n}",
        "func f(_ n: &Int) -> Int { n }",
        "func f() -> Enemy { makeEnemy() }",
        "func f() -> Stats { makeEnemy().stats }",
    ])
    func `a moved place, a copy, an implicitly copyable place or a value is returned as written`(function: String) {
        #expect(messages(of: function) == [])
    }
}

struct InitializerArgumentPlaceTests {
    @Test func `a place given bare to an initializer's argument names 'consume' and 'copy'`() {
        #expect(messages(of: "func f() {\n    let grid = [1, 2]\n    _ = Board(grid: grid)\n}") == [
            "8:21: error[E0292]: 'Board' takes a [2 of Int]; write 'consume grid' or 'copy grid'",
        ])
    }

    @Test func `a place the code can't move out of, given bare to an initializer's argument, names 'copy' alone`() {
        #expect(messages(of: "func f(_ s: &Stats) -> Enemy { Enemy(stats: s) }") == [
            "6:45: error[E0292]: 'Enemy' takes a Stats; write 'copy s'",
        ])
    }

    @Test(arguments: [
        "func f() -> Board {\n    let grid = [1, 2]\n    return Board(grid: consume grid)\n}",
        "func f(_ s: &Stats) -> Enemy { Enemy(stats: copy s) }",
        "func f() -> Enemy { Enemy(stats: Stats(hp: 1)) }",
        "func f() -> Stats {\n    let n = 1\n    return Stats(hp: n)\n}",
    ])
    func `a moved place, a copy, an implicitly copyable place or a value is given as written`(function: String) {
        #expect(messages(of: function) == [])
    }
}

struct ArrayElementPlaceTests {
    @Test func `each place given bare as an array literal's element names 'consume' and 'copy'`() {
        let function = "func f() {\n    let e = makeEnemy()\n    let g = makeEnemy()\n    _ = [e, g]\n}"
        #expect(messages(of: function) == [
            "9:10: error[E0298]: an array literal's element takes an Enemy; write 'consume e' or 'copy e'",
            "9:13: error[E0298]: an array literal's element takes an Enemy; write 'consume g' or 'copy g'",
        ])
    }

    @Test func `a place the code can't move out of, given bare as an element, names 'copy' alone`() {
        #expect(messages(of: "func f(_ e: &Enemy) -> [1 of Enemy] { [e] }") == [
            "6:40: error[E0298]: an array literal's element takes an Enemy; write 'copy e'",
        ])
    }

    @Test(arguments: [
        "func f() -> [2 of Enemy] {\n    let e = makeEnemy()\n    let g = makeEnemy()\n"
            + "    return [consume e, copy g]\n}",
        "func f() -> [2 of Int] {\n    let n = 1\n    return [n, n]\n}",
        "func f() -> [2 of Enemy] { [makeEnemy(), Enemy(stats: Stats(hp: 2))] }",
        "func f(_ e: &Enemy) -> [2 of Enemy] { .init(repeating: e) }",
    ])
    func `a moved place, a copy, an implicitly copyable place or a value is an element as written`(function: String) {
        #expect(messages(of: function) == [])
    }
}
