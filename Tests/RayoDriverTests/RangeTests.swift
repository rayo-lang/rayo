import Testing
import RayoDriver

struct RangeTests {
    @Test("an error covers the expression or the name it's about", arguments: [
        ("let x: Bool = 1 + 2", "1 + 2"),
        ("let x: Bool = (1 + 2)", "(1 + 2)"),
        ("let x: Bool = -1", "-1"),
        ("var a = 1\nlet x: Bool = -a", "-a"),
        ("if true == 1 < 2 { }", "true == 1"),
        ("var x = 1\nx += true", "x += true"),
        ("break", "break"),
        ("let x: Bool = print(1)", "print(1)"),
        ("var a = 1\nlet b: Bool = copy a", "copy a"),
        ("print(1, 2)", "print(1, 2)"),
        ("print(1) + 2", "print(1) + 2"),
        ("let x = 1\nx = 2", "x"),
        ("let x = 1\nlet x = 2", "x"),
        ("if 1 { }", "1"),
    ])
    func covered(body: String, text: String) {
        let source = "func main() {\n\(body)\n}"
        #expect(coveredText(diagnostics(source), in: source) == [text])
    }
}
