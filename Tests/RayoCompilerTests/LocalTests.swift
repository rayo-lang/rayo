import Testing
import RayoDiagnostics

struct LocalTests {
    @Test("locals are checked", arguments: [
        ("let x = 1\nx = 2", ErrorCode.letAssignedTwice(name: "x")),
        ("let x = 1\nx += 2", .letAssignedTwice(name: "x")),
    ])
    func rejected(body: String, expected: ErrorCode) {
        #expect(errors("func main() {\n\(body)\n}") == [expected])
    }
}
