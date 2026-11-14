import Testing

@Suite("Lowering expressions")
struct ExpressionLoweringTests {
    @Test func `an operand that is itself an operation is computed first, into a temporary`() throws {
        try expectLowering(ofMain: "let x = 1 + 2 * 3", toMatch: "nested-operation")
    }

    @Test func `a local used as an operand is read, and a local that gives a declaration its value is moved`() throws {
        try expectLowering(ofMain: "let a = 1\nlet b = -a\nlet c = a", toMatch: "reads-and-moves")
    }

    @Test func `'!' applies to its operand as '-' does`() throws {
        try expectLowering(ofMain: "let a = true\nlet b = !a", toMatch: "not")
    }

    @Test func `'copy' reads a local where a bare local would be moved`() throws {
        try expectLowering(ofMain: "let a = 1\nlet b = copy a", toMatch: "copy")
    }

    @Test
    func `'&&' evaluates its right operand in a block of its own, which only a true left operand reaches`() throws {
        try expectLowering(ofMain: "let a = true\nlet b = a && false", toMatch: "and")
    }

    @Test
    func `'||' evaluates its right operand in a block of its own, which only a false left operand reaches`() throws {
        try expectLowering(ofMain: "let a = true\nlet b = a || false", toMatch: "or")
    }

    @Test
    func `a '&&' that is the left operand of '||' is decided first, and its result decides whether '||' goes on`()
        throws {
        let body = "let a = true\nlet b = false\nlet c = true\nlet d = a && b || c"
        try expectLowering(ofMain: body, toMatch: "and-inside-or")
    }

    @Test
    func `a '||' that is the right operand of '&&' is lowered in the block that evaluates it, and joins before it`()
        throws {
        let body = "let a = true\nlet b = false\nlet c = true\nlet d = a && (b || c)"
        try expectLowering(ofMain: body, toMatch: "or-inside-and")
    }

    @Test func `a '||' that is a call's argument passes the temporary that holds its result`() throws {
        let source = "func main() {\nlet a = true\nshow(a || false)\n}\nfunc show(_ b: Bool) {}"
        try expectLowering(of: source, toMatch: "or-as-argument")
    }

    @Test func `each operator on Ints and Bools computes its value from its operands`() throws {
        let source = """
            func main() {
                let a = 7
                let b = 2
                print(a + b)
                print(a - b)
                print(a * b)
                print(a / b)
                print(a % b)
                print(-a)
                print(a == b)
                print(a != b)
                print(a < b)
                print(a <= b)
                print(a > b)
                print(a >= b)
                let t = true
                print(!t)
                print(t == false)
                print(t != false)
            }
            """
        try expectLowering(of: source, toMatch: "operators")
    }
}
