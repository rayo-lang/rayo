import Testing

@Suite("Lowering statements")
struct StatementLoweringTests {
    @Test func `a declaration starts its local's life, then stores its value in it`() throws {
        try expectLowering(ofMain: "let x = 1", toMatch: "declaration")
    }

    @Test func `an expression statement computes its value and keeps it nowhere`() throws {
        try expectLowering(ofMain: "print(1 + 2)", toMatch: "expression-statement")
    }

    @Test func `a declaration without a value only starts its local's life`() throws {
        try expectLowering(ofMain: "var x: Int\nx = 1", toMatch: "declaration-without-value")
    }

    @Test func `a declaration of several locals without values starts each one's life`() throws {
        try expectLowering(ofMain: "let a: Int, b: Int\na = 1\nb = 2", toMatch: "declarations-without-values")
    }

    @Test func `a later local of a declaration is declared after, and reads, an earlier one`() throws {
        let body = "let a = 1, b = copy a + 1, c: Int\nc = 3\nprint(a + b + c)"
        try expectLowering(ofMain: body, toMatch: "several-bindings")
    }

    @Test func `an assignment stores its value in the local`() throws {
        try expectLowering(ofMain: "var x = 1\nx = 2", toMatch: "assignment")
    }

    @Test func `a compound assignment applies its operator to the local and the value`() throws {
        try expectLowering(ofMain: "var x = 1\nx += 3", toMatch: "compound-assignment")
    }

    @Test
    func `a compound assignment computes a value that is an operation into a temporary, then applies its operator`()
        throws {
        try expectLowering(ofMain: "var x = 1\nx += 2 * 3", toMatch: "compound-assignment-of-operation")
    }

    @Test func `each compound assignment applies its own operator`() throws {
        let body = "var x = 9\nx += 1\nx -= 2\nx *= 3\nx /= 4\nx %= 5"
        try expectLowering(ofMain: body, toMatch: "compound-assignments")
    }
}
