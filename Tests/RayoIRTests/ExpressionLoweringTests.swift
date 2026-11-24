import Testing

@Suite("Lowering expressions")
struct ExpressionLoweringTests {
    @Test func `an operand that is itself an operation is computed first, into a temporary`() throws {
        try expectLowering(ofMain: "let x = 1 + 2 * 3", toMatch: "nested-operation")
    }

    @Test func `a temporary's life starts where lowering makes it, on each pass of a loop`() throws {
        let body = """
            var i = 0
            while i < 3 {
                print(i * 2)
                i += 1
            }
            """
        try expectLowering(ofMain: body, toMatch: "temporary-declarations")
    }

    @Test func `a local used as an operand is read, and a local that 'consume' names is moved`() throws {
        try expectLowering(ofMain: "let a = 1\nlet b = -a\nlet c = consume a", toMatch: "reads-and-moves")
    }

    @Test
    func `'_ =', an assignment and a 'consume' in an 'if' move a local, and a borrowed argument's 'if' reads it`()
        throws {
        let source = """
            func main() {
                let a = Hit(damage: 1)
                var b = Hit(damage: 2)
                b = consume a
                _ = consume b
                let t = true
                let d = Hit(damage: 3)
                let e = if t { consume d } else { Hit(damage: 4) }
                let g = Hit(damage: 5)
                show(if t { &g } else { &e })
            }
            func show(_ h: &Hit) {}
            struct Hit(let damage: Int)
            """
        try expectLowering(of: source, toMatch: "taken-positions")
    }

    @Test func `a position that takes an Int, a UInt or a Bool from a place copies it, so the place keeps its value`()
        throws {
        // A `_ =`, an initializer's argument, an array literal's element, a branch of an `if` in such a position and
        // a `return` each read the place.
        let source = """
            func main() {}
            func kept(_ n: Int, _ level: UInt, _ alive: Bool) -> Int {
                _ = alive
                let s = Score(points: n, level: level)
                let all = [n, if alive { n } else { 0 }]
                return n
            }
            struct Score(let points: Int, let level: UInt)
            """
        try expectLowering(of: source, toMatch: "copied-scalars")
    }

    @Test func `a local in parentheses is copied where the bare local would be, and read where it would be`() throws {
        try expectLowering(ofMain: "let a = 1\nlet b = (a)\nprint((b))", toMatch: "parenthesized-local")
    }

    @Test func `'!' applies to its operand as '-' does`() throws {
        try expectLowering(ofMain: "let a = true\nlet b = !a", toMatch: "not")
    }

    @Test func `'copy' reads a local where a bare local would be moved`() throws {
        let source = """
            func main() {
                let a = Hit(damage: 1)
                let b = copy a
            }
            struct Hit(let damage: Int)
            """
        try expectLowering(of: source, toMatch: "copy")
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
