import Testing
import RayoDiagnostics

struct UnusedValueTests {
    @Test func `a parameter that owns its argument, which no code reads, is reported where it is declared`() {
        let source = "func main() {\n    show(1, 2)\n}\nfunc show(_ n: Int, _ m: Int) {\n    print(m)\n}"
        #expect(diagnostics(source).map(\.description) == [
            "4:13: error[E0318]: the parameter 'n' is never read; write '_ = n' to drop it",
        ])
    }

    // A parameter that borrows its argument holds a value its caller owns, so nothing is lost when no code reads it.
    @Test(arguments: ["func show(_ n: Int) {\n    _ = n\n}", "func show(_ n: &Int) {}"])
    func `a parameter dropped with '_ =', or one that borrows its argument, needs no read`(function: String) {
        let call = function.contains("&") ? "show(&a)" : "show(a)"
        #expect(errors("func main() {\n    let a = 1\n    \(call)\n}\n\(function)") == [])
    }
}
