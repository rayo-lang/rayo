import Testing

struct RangeTests {
    @Test("an error covers the expression or the name it's about", arguments: [
        ("let x = 1\nx = 2", "x"),
    ])
    func covered(body: String, text: String) {
        let source = "func main() {\n\(body)\n}"
        #expect(coveredText(diagnostics(source), in: source) == [text])
    }
}
