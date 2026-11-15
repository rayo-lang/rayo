import Testing
import RayoDiagnostics

struct ParameterTests {
    @Test("a parameter is borrowed: it can't change, and an expression reads it", arguments: [
        ("func f(x: Int) -> Int { copy x + x }", [ErrorCode]()),
    ])
    func borrowed(declaration: String, expected: [ErrorCode]) {
        #expect(errors("func main() {}\n" + declaration) == expected)
    }
}
