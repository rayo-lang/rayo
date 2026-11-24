import Testing
import RayoDiagnostics

/// The declarations the tests' bodies use: a struct, and functions that borrow their arguments for change, beside
/// another they borrow for change or share.
private let declarations = """
    struct Enemy(var hp: Int, var armor: Int)
    func bump(_ n: mutable &Int) { n += 1 }
    func both(_ m: mutable &Int, _ n: mutable &Int) { m += n }
    func beside(_ m: mutable &Int, _ n: &Int) { m += n }
    func heal(_ e: mutable &Enemy, by n: &Int) { e.hp += n }
    """

/// The diagnostics that `body`, as `main`'s body, reports, each as its description followed by its notes. The body
/// starts on the source's second line.
private func reports(ofMain body: String) -> [String] {
    diagnostics("func main() {\n\(body)\n}\n\(declarations)").flatMap { [$0.description] + $0.notes }
}

/// The diagnostics that `statement`, after locals that it lends and reads, reports. The statement is on the
/// source's fifth line.
private func reports(of statement: String) -> [String] {
    let locals = "    var x = 1\n    var e = Enemy(hp: 1, armor: 2)\n    var a = [1, 2]"
    return reports(ofMain: "\(locals)\n    \(statement)\n    print(x + e.hp + a[0])")
}

struct MutableParameterTests {
    // Distinct fields, and elements at literal indices that differ, are disjoint.
    @Test(arguments: [
        "both(mutable e.hp, mutable e.armor)", "both(mutable a[0], mutable a[1])", "beside(mutable e.hp, e.armor)",
        "heal(mutable e, by: x)", "bump(mutable x)\n    bump(mutable x)",
    ])
    func `lends for change of disjoint places, or one after another, compile`(statement: String) {
        #expect(reports(of: statement) == [])
    }

    @Test(arguments: [
        ("beside(mutable x, x)", "5:23: error[E0312]: 'x' can't be used while 'x' is mutably borrowed", 20),
        ("both(mutable x, mutable x)", "5:29: error[E0312]: 'x' can't be used while 'x' is mutably borrowed", 18),
        ("beside(mutable e.hp, e.hp)", "5:26: error[E0312]: 'e.hp' can't be used while 'e.hp' is mutably borrowed", 20),
        ("heal(mutable e, by: e.hp)", "5:25: error[E0312]: 'e.hp' can't be used while 'e' is mutably borrowed", 18),
    ])
    func `a call that lends a place for change and accesses it in another argument is reported`(
        statement: String, error: String, lentColumn: Int,
    ) {
        #expect(reports(of: statement) == [error, "5:\(lentColumn): note: mutably borrowed here"])
    }

    // An index that isn't known as the program is checked may be the other's, so each lends the whole array.
    @Test func `lends for change of elements at indices that a local holds are reported`() {
        let body = "    var a = [1, 2]\n    let i: UInt = 0\n    let j: UInt = 1\n    both(mutable a[i], mutable a[j])"
        #expect(reports(ofMain: "\(body)\n    print(a[0])") == [
            "5:32: error[E0312]: 'a' can't be used while 'a' is mutably borrowed", "5:18: note: mutably borrowed here",
        ])
    }

    @Test func `a 'ref let' used after a lend for change of its place is reported`() {
        #expect(reports(ofMain: "    var x = 1\n    ref let r = &x\n    bump(mutable x)\n    print(r)") == [
            "4:18: error[E0313]: 'x' can't change while 'x' is borrowed", "3:17: note: borrowed here",
        ])
    }

    @Test func `a lend for change of a local that holds no value yet is reported`() {
        #expect(reports(ofMain: "    var x: Int\n    bump(mutable x)\n    print(x)") == [
            "3:18: error[E0304]: 'x' isn't initialized",
        ])
    }
}
