import Testing

@Suite("Lowering branches and loops")
struct ControlFlowLoweringTests {
    @Test func `an 'if' branches to a block for each branch, and both go on to a block after them`() throws {
        try expectLowering(ofMain: "let c = true\nif c { print(1) } else { print(2) }", toMatch: "if-else")
    }

    @Test func `an 'else if' is an 'if' in the 'else' branch, as a statement and as a value`() throws {
        let body = """
            let n = 2
            if n < 0 { print(1) } else if n == 0 { print(2) } else { print(3) }
            let sign = if n < 0 { -1 } else if n == 0 { 0 } else { 1 }
            print(sign)
            """
        try expectLowering(ofMain: body, toMatch: "else-if")
    }

    @Test func `an 'if' that is an operand, an argument, a result or a branch's value gives its value there`() throws {
        let source = """
            func main() {
                let c = true
                var x = 1 + if c { 2 } else { 3 }
                x += if c { 4 } else { 5 }
                let y = -if c { copy x } else { 6 }
                let p = Point(x: if c { 7 } else { 8 })
                let z = if c { if c { 9 } else { 10 } } else {
                    print(1)
                    11
                }
                print(y + z + p.x)
            }
            func sign(_ n: Int) -> Int { return if n < 0 { -1 } else { 1 } }
            struct Point(let x: Int)
            """
        try expectLowering(of: source, toMatch: "if-in-expressions")
    }

    @Test func `an 'if' without 'else' branches to an empty block where its condition fails`() throws {
        try expectLowering(ofMain: "let c = true\nif c { print(1) }", toMatch: "if-without-else")
    }

    @Test func `an 'if' whose condition is a '&&' branches on the temporary that holds its result`() throws {
        try expectLowering(ofMain: "let a = true\nlet b = false\nif a && b { print(1) }", toMatch: "if-and")
    }

    @Test func `a 'return' in a branch leaves the function, and the rest of the branch goes on to the join`() throws {
        try expectLowering(ofMain: "let c = true\nif c { return }\nprint(1)", toMatch: "return-in-branch")
    }

    @Test
    func `an 'if' computes each branch's value into a temporary, and a declaration takes it from there once`() throws {
        try expectLowering(ofMain: "let c = true\nlet y = if c { 1 } else { 2 }", toMatch: "if-into-local")
    }

    @Test
    func `an 'if' whose branch ends in 'return', 'break' or 'continue' leaves, and the other gives its value`() throws {
        let source = """
            func main() {
                var i = 0
                while true {
                    i += 1
                    let odd = if i % 2 == 0 { continue } else { copy i }
                    let next = if odd > 7 { break } else { odd }
                    print(next)
                }
            }
            func half(_ n: Int) -> Int {
                let even = if n % 2 == 0 { copy n } else { return -1 }
                return even / 2
            }
            func pick(_ c: Bool) -> Int {
                print(0)
                show(if c { return 1 } else { return 2 })
            }
            func show(_ n: Int) {}
            """
        try expectLowering(of: source, toMatch: "if-branch-leaves")
    }

    @Test func `an 'if' whose value is dropped computes each branch's value for what it does`() throws {
        try expectLowering(ofMain: "let c = true\n_ = if c { print(1) } else { print(2) }", toMatch: "if-dropped")
    }

    @Test func `an 'if' that is a call's argument passes the temporary its branches compute`() throws {
        let source = "func main() {\nlet c = true\nshow(if c { 1 } else { 2 })\n}\nfunc show(_ n: Int) {}"
        try expectLowering(of: source, toMatch: "if-as-argument")
    }

    @Test
    func `a 'while' tests its condition in a header, whose body goes back to it, and whose exit goes on`() throws {
        try expectLowering(ofMain: "var i = 0\nwhile i < 3 { i += 1 }", toMatch: "while")
    }

    @Test
    func `a 'while' whose condition is a '&&' branches where the '&&' joins, and its body goes back to the header`()
        throws {
        try expectLowering(ofMain: "var a = true\nlet b = false\nwhile a && b { a = false }", toMatch: "while-and")
    }

    @Test func `a 'while true' header goes straight to its body, and a 'break' goes to the exit`() throws {
        try expectLowering(ofMain: "while true { break }", toMatch: "while-true-break")
    }

    @Test func `a 'continue' goes back to the header`() throws {
        try expectLowering(ofMain: "var i = 0\nwhile i < 2 {\ni += 1\ncontinue\n}", toMatch: "continue")
    }

    @Test func `'continue' goes back to the innermost loop's header`() throws {
        let body = "var i = 0\nwhile i < 2 {\ni += 1\nwhile true { continue }\n}"
        try expectLowering(ofMain: body, toMatch: "continue-innermost")
    }

    @Test func `'break' leaves the innermost loop`() throws {
        try expectLowering(ofMain: "while true {\nwhile true { break }\nbreak\n}", toMatch: "break-innermost")
    }

    @Test func `a 'return' leaves the function, and the code after it goes in a block of its own`() throws {
        try expectLowering(ofMain: "print(1)\nreturn\nprint(2)", toMatch: "return-then-code")
    }
}
