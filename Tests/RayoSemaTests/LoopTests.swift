import Testing

struct LoopTests {
    @Test("'break' and 'continue' need a loop", arguments: ["break", "continue"])
    func outsideLoop(keyword: String) {
        #expect(errors("func main() {\n\(keyword)\n}") == [.outsideLoop(keyword: keyword)])
    }
}
