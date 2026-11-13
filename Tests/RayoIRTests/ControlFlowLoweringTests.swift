import RayoIR
import RayoSema
import Testing

@Suite("Lowering branches and loops")
struct ControlFlowLoweringTests {
    @Test("an 'if' branches to a block for each branch, and both go on to a block after them")
    func ifElse() throws(RejectedSource) {
        let main = try loweredMain("let c = true\nif c { print(1) } else { print(2) }")
        let expected = mainFunction(
            locals: [letLocal("c", .bool)],
            block(declare(0), compute(0, .use(bool(true))), then: branch(read(0), then: 1, otherwise: 2)),
            block(compute(nil, .call(.printInt, arguments: [int(1)])), then: goto(3)),
            block(compute(nil, .call(.printInt, arguments: [int(2)])), then: goto(3)),
            block(then: .return(nil)),
        )
        #expect(main == expected)
    }

    @Test func `an 'if' without 'else' branches to an empty block where its condition fails`() throws(RejectedSource) {
        let main = try loweredMain("let c = true\nif c { print(1) }")
        let expected = mainFunction(
            locals: [letLocal("c", .bool)],
            block(declare(0), compute(0, .use(bool(true))), then: branch(read(0), then: 1, otherwise: 2)),
            block(compute(nil, .call(.printInt, arguments: [int(1)])), then: goto(3)),
            block(then: goto(3)),
            block(then: .return(nil)),
        )
        #expect(main == expected)
    }

    @Test("an 'if' whose condition is a '&&' branches on the temporary that holds its result")
    func ifAnd() throws(RejectedSource) {
        let main = try loweredMain("let a = true\nlet b = false\nif a && b { print(1) }")
        let expected = mainFunction(
            locals: [letLocal("a", .bool), letLocal("b", .bool), .temporary(.bool)],
            block(
                declare(0), compute(0, .use(bool(true))),
                declare(1), compute(1, .use(bool(false))),
                compute(2, .use(read(0))),
                then: branch(read(2), then: 1, otherwise: 2),
            ),
            block(compute(2, .use(read(1))), then: goto(2)),
            // The `if` starts where the `&&` joins.
            block(then: branch(read(2), then: 3, otherwise: 4)),
            block(compute(nil, .call(.printInt, arguments: [int(1)])), then: goto(5)),
            block(then: goto(5)),
            block(then: .return(nil)),
        )
        #expect(main == expected)
    }

    @Test("a 'return' in a branch leaves the function, and the rest of the branch goes on to the join")
    func returnInBranch() throws(RejectedSource) {
        let main = try loweredMain("let c = true\nif c { return }\nprint(1)")
        let expected = mainFunction(
            locals: [letLocal("c", .bool)],
            block(declare(0), compute(0, .use(bool(true))), then: branch(read(0), then: 1, otherwise: 2)),
            block(then: .return(nil)),
            block(then: goto(3)),
            block(compute(nil, .call(.printInt, arguments: [int(1)])), then: .return(nil)),
            // The code after the `return`, which no path reaches, ends the branch.
            block(then: goto(3)),
        )
        #expect(main == expected)
    }

    @Test("an 'if' computes each branch's value into a temporary, and a declaration takes it from there once")
    func ifIntoLocal() throws(RejectedSource) {
        let main = try loweredMain("let c = true\nlet y = if c { 1 } else { 2 }")
        let expected = mainFunction(
            locals: [letLocal("c", .bool), letLocal("y", .int), .temporary(.int)],
            block(
                declare(0), compute(0, .use(bool(true))),
                declare(1),
                then: branch(read(0), then: 1, otherwise: 2),
            ),
            block(compute(2, .use(int(1))), then: goto(3)),
            block(compute(2, .use(int(2))), then: goto(3)),
            block(compute(1, .use(read(2))), then: .return(nil)),
        )
        #expect(main == expected)
    }

    @Test func `an 'if' whose value is dropped computes each branch's value for what it does`() throws(RejectedSource) {
        let main = try loweredMain("let c = true\n_ = if c { print(1) } else { print(2) }")
        let expected = mainFunction(
            locals: [letLocal("c", .bool)],
            block(declare(0), compute(0, .use(bool(true))), then: branch(read(0), then: 1, otherwise: 2)),
            block(compute(nil, .call(.printInt, arguments: [int(1)])), then: goto(3)),
            block(compute(nil, .call(.printInt, arguments: [int(2)])), then: goto(3)),
            block(then: .return(nil)),
        )
        #expect(main == expected)
    }

    @Test func `an 'if' that is a call's argument passes the temporary its branches compute`() throws(RejectedSource) {
        let program = try lowered("func main() {\nlet c = true\nshow(if c { 1 } else { 2 })\n}\nfunc show(_ n: Int) {}")
        let expected = mainFunction(
            locals: [letLocal("c", .bool), .temporary(.int)],
            block(declare(0), compute(0, .use(bool(true))), then: branch(read(0), then: 1, otherwise: 2)),
            block(compute(1, .use(int(1))), then: goto(3)),
            block(compute(1, .use(int(2))), then: goto(3)),
            block(compute(nil, .call(.function(FunctionID(index: 1)), arguments: [read(1)])), then: .return(nil)),
        )
        #expect(program.body(at: 0) == expected)
    }

    @Test("a 'while' tests its condition in a header, whose body goes back to it, and whose exit goes on")
    func whileLoop() throws(RejectedSource) {
        let main = try loweredMain("var i = 0\nwhile i < 3 { i += 1 }")
        let expected = mainFunction(
            locals: [varLocal("i", .int), .temporary(.bool)],
            block(declare(0), compute(0, .use(int(0))), then: goto(1)),
            block(compute(1, .binary(.less, read(0), int(3))), then: branch(read(1), then: 2, otherwise: 3)),
            block(compute(0, .binary(.add, read(0), int(1))), then: goto(1)),
            block(then: .return(nil)),
        )
        #expect(main == expected)
    }

    @Test("a 'while' whose condition is a '&&' branches where the '&&' joins, and its body goes back to the header")
    func whileAnd() throws(RejectedSource) {
        let main = try loweredMain("var a = true\nlet b = false\nwhile a && b { a = false }")
        let expected = mainFunction(
            locals: [varLocal("a", .bool), letLocal("b", .bool), .temporary(.bool)],
            block(declare(0), compute(0, .use(bool(true))), declare(1), compute(1, .use(bool(false))), then: goto(1)),
            // The header starts the `&&` with `a`.
            block(compute(2, .use(read(0))), then: branch(read(2), then: 4, otherwise: 5)),
            // The body goes back to the header, where the `&&` starts again.
            block(compute(0, .use(bool(false))), then: goto(1)),
            block(then: .return(nil)),
            block(compute(2, .use(read(1))), then: goto(5)),
            // The `&&`'s join goes on to the body or the exit.
            block(then: branch(read(2), then: 2, otherwise: 3)),
        )
        #expect(main == expected)
    }

    @Test("a 'while true' header goes straight to its body, and a 'break' goes to the exit")
    func whileTrue() throws(RejectedSource) {
        let main = try loweredMain("while true { break }")
        let expected = mainFunction(
            block(then: goto(1)),
            block(then: goto(2)),
            block(then: goto(3)),
            block(then: .return(nil)),
            // The code after the `break`, which no path reaches, goes back to the header.
            block(then: goto(1)),
        )
        #expect(main == expected)
    }

    @Test func `a 'continue' goes back to the header`() throws(RejectedSource) {
        let main = try loweredMain("var i = 0\nwhile i < 2 {\ni += 1\ncontinue\n}")
        let expected = mainFunction(
            locals: [varLocal("i", .int), .temporary(.bool)],
            block(declare(0), compute(0, .use(int(0))), then: goto(1)),
            block(compute(1, .binary(.less, read(0), int(2))), then: branch(read(1), then: 2, otherwise: 3)),
            block(compute(0, .binary(.add, read(0), int(1))), then: goto(1)),
            block(then: .return(nil)),
            block(then: goto(1)),
        )
        #expect(main == expected)
    }

    @Test func `'continue' goes back to the innermost loop's header`() throws(RejectedSource) {
        let main = try loweredMain("var i = 0\nwhile i < 2 {\ni += 1\nwhile true { continue }\n}")
        let expected = mainFunction(
            locals: [varLocal("i", .int), .temporary(.bool)],
            block(declare(0), compute(0, .use(int(0))), then: goto(1)),
            // The outer loop's header, body and exit.
            block(compute(1, .binary(.less, read(0), int(2))), then: branch(read(1), then: 2, otherwise: 3)),
            block(compute(0, .binary(.add, read(0), int(1))), then: goto(4)),
            block(then: .return(nil)),
            // The inner loop's header and body, whose `continue` goes to the inner header.
            block(then: goto(5)),
            block(then: goto(4)),
            // The inner exit, which ends the outer body.
            block(then: goto(1)),
            // The code after the `continue`, which no path reaches, ends the inner body.
            block(then: goto(4)),
        )
        #expect(main == expected)
    }

    @Test func `'break' leaves the innermost loop`() throws(RejectedSource) {
        let main = try loweredMain("while true {\nwhile true { break }\nbreak\n}")
        let expected = mainFunction(
            block(then: goto(1)),
            // The outer loop's header, body and exit.
            block(then: goto(2)),
            block(then: goto(4)),
            block(then: .return(nil)),
            // The inner loop's header and body, whose `break` goes to the inner exit.
            block(then: goto(5)),
            block(then: goto(6)),
            // The inner exit, whose `break` goes to the outer exit.
            block(then: goto(3)),
            // The code after the inner `break`, which no path reaches, ends the inner body.
            block(then: goto(4)),
            // The code after the outer `break`, which no path reaches, ends the outer body.
            block(then: goto(1)),
        )
        #expect(main == expected)
    }

    @Test("a 'return' leaves the function, and the code after it goes in a block of its own")
    func returnFromVoid() throws(RejectedSource) {
        let main = try loweredMain("print(1)\nreturn\nprint(2)")
        let expected = mainFunction(
            block(compute(nil, .call(.printInt, arguments: [int(1)])), then: .return(nil)),
            block(compute(nil, .call(.printInt, arguments: [int(2)])), then: .return(nil)),
        )
        #expect(main == expected)
    }
}
