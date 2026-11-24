import Testing

/// The declarations the tests' bodies use: a struct with a nested struct and an array in it, functions that own a
/// value of each, and `h`, which one overload owns and another borrows.
private let declarations = """
    struct Enemy(var stats: Stats, var slots: [2 of Int])
    struct Stats(var hp: Int)
    func makeEnemy() -> Enemy { Enemy(stats: Stats(hp: 1), slots: [1, 2]) }
    func keep(_ e: Enemy) {}
    func keepStats(_ s: Stats) {}
    func total(_ a: [2 of Int]) {}
    func h(_ e: Enemy) {}
    func h(_ e: &Enemy) {}
    """

/// The locals the tests' bodies start from.
private let locals = """
    var e = makeEnemy()
        let a: [2 of Int] = [1, 2]
        var g: [2 of Enemy] = [makeEnemy(), makeEnemy()]
        var i: UInt = 1
        var c = true
    """

/// The errors that `statement`, after `locals` in `main`'s body, reports, each as its column, code and message.
private func messages(of statement: String) -> [String] {
    errorLines(inMain: "\(locals)\n    \(statement)", beside: declarations).map { line in
        String(line.drop { $0 != ":" }.dropFirst())
    }
}

/// The errors that `function`, beside an empty `main` and the declarations, reports, each as its position, code and
/// message.
private func functionMessages(of function: String) -> [String] {
    diagnostics("func main() {}\n\(declarations)\n\(function)").map(\.description)
}

struct OwningParameterTests {
    @Test(arguments: [
        "keep(consume e)", "keep(copy e)", "keep(makeEnemy())", "keep(Enemy(stats: Stats(hp: 2), slots: [3, 4]))",
        "keepStats(consume e.stats)", "keepStats(copy g[i].stats)", "total(consume e.slots)", "total(copy a)",
        "total([5, 6])", "total(.init(repeating: 0))", "keep(if c { consume e } else { makeEnemy() })",
        "h(consume e)", "h(&e)", "h(makeEnemy())", "ref let r = &e\n    h(r)",
    ])
    func `a parameter that owns a struct or an array takes a moved place, a copy, or a value`(statement: String) {
        #expect(messages(of: statement) == [])
    }

    @Test(arguments: [
        ("keep(e)", 10, "keep", "an Enemy", "e"), ("keepStats(e.stats)", 15, "keepStats", "a Stats", "e.stats"),
        ("total(a)", 11, "total", "a [2 of Int]", "a"), ("total(e.slots)", 11, "total", "a [2 of Int]", "e.slots"),
    ])
    func `a place given bare to a parameter that owns it names 'consume' and 'copy'`(
        statement: String, column: Int, callee: String, type: String, place: String,
    ) {
        #expect(messages(of: statement) == [
            "\(column): error[E0292]: '\(callee)' takes \(type); write 'consume \(place)' or 'copy \(place)'",
        ])
    }

    @Test(arguments: [
        ("keep(g[0])", 10, "keep", "an Enemy", "g[0]"), ("keep(g[i])", 10, "keep", "an Enemy", "g[i]"),
        ("keepStats(g[i].stats)", 15, "keepStats", "a Stats", "g[i].stats"),
        ("ref let r = &e\n    keep(r)", 10, "keep", "an Enemy", "r"),
        ("ref let r = &e\n    total(r.slots)", 11, "total", "a [2 of Int]", "r.slots"),
    ])
    func `a place the code can't move out of, given bare to a parameter that owns it, names 'copy' alone`(
        statement: String, column: Int, callee: String, type: String, place: String,
    ) {
        #expect(messages(of: statement) == [
            "\(column): error[E0292]: '\(callee)' takes \(type); write 'copy \(place)'",
        ])
    }

    @Test(arguments: [
        ("func f(_ e: &Enemy) { keep(e) }", "10:28", "keep", "an Enemy", "e"),
        ("func f(_ e: &Enemy) { keepStats(e.stats) }", "10:33", "keepStats", "a Stats", "e.stats"),
        ("func f(_ a: &[2 of Int]) { total(a) }", "10:34", "total", "a [2 of Int]", "a"),
    ])
    func `a borrowed parameter given bare to a parameter that owns it names 'copy' alone`(
        function: String, position: String, callee: String, type: String, place: String,
    ) {
        #expect(functionMessages(of: function) == [
            "\(position): error[E0292]: '\(callee)' takes \(type); write 'copy \(place)'",
        ])
    }

    @Test func `an owning parameter given bare to another that owns it names 'consume' and 'copy'`() {
        #expect(functionMessages(of: "func f(_ e: Enemy) { keep(e) }") == [
            "10:27: error[E0292]: 'keep' takes an Enemy; write 'consume e' or 'copy e'",
        ])
    }

    @Test func `each branch of an 'if' given bare to a parameter that owns it names the marks that fit it`() {
        #expect(messages(of: "keep(if c { e } else { g[0] })") == [
            "17: error[E0292]: 'keep' takes an Enemy; write 'consume e' or 'copy e'",
            "28: error[E0292]: 'keep' takes an Enemy; write 'copy g[0]'",
        ])
    }

    // The overload that owns its argument takes the place as written, so it is the one the call reaches.
    @Test(arguments: [("h(e)", 7, "'consume e', 'copy e' or '&e'"), ("h(g[0])", 7, "'copy g[0]' or '&g[0]'")])
    func `a place given bare where an overload borrows it names '&' too`(
        statement: String, column: Int, marks: String,
    ) {
        #expect(messages(of: statement) == ["\(column): error[E0292]: 'h' takes an Enemy; write \(marks)"])
    }
}
