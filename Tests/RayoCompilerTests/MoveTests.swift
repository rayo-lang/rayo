import Testing
import RayoDiagnostics

struct MoveTests {
    @Test func `a move out of a borrowed parameter waits to be reported until the program checks`() {
        let source = "func main() {}\nfunc f(x: Int) {\n    let y = x\n    let z: Bool = 1\n}"
        #expect(diagnostics(source).map(\.code) == [.typeMismatch(expected: "Bool", found: "Int")])
    }

    // A field taken from a `copy` moves out of the copy, so the local or parameter it copies keeps it.
    @Test(arguments: [
        "func f() -> Int {\n    let e = E(a: S(n: 1))\n    let s = (copy e).a\n    return e.a.n + s.n\n}",
        "func f(e: E) -> S { (copy e).a }",
    ])
    func `a field taken from a copy moves out of the copy`(function: String) {
        let source = "func main() {}\n\(function)\nstruct E(var a: S)\nstruct S(var n: Int)"
        #expect(errors(source) == [])
    }

    // A `copy` is a value, not a place. As with any temporary, its elements can't be moved out of it; `copy a[0]`
    // copies the element instead.
    @Test func `an element taken from a copy can't be moved out of the copy`() {
        let source = "func main() {}\nfunc f(a: [2 of S]) -> S { (copy a)[0] }\nstruct S(var n: Int)"
        #expect(errors(source) == [.moveFromElement])
    }
}
