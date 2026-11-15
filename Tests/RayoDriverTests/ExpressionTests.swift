import Testing

struct ExpressionTests {
    @Test func `a program prints the value of an expression whose parentheses group it`() {
        #expect(output("print((2 + 3) * 4 - 20 % 6 / 2)") == "19\n")
    }
}
