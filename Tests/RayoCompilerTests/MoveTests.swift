import Testing
import RayoDiagnostics

struct MoveTests {
    @Test func `a move out of a borrowed parameter waits to be reported until the program checks`() {
        let source = "func main() {}\nfunc f(x: Int) {\n    let y = x\n    let z: Bool = 1\n}"
        #expect(diagnostics(source).map(\.code) == [.typeMismatch(expected: "Bool", found: "Int")])
    }
}
