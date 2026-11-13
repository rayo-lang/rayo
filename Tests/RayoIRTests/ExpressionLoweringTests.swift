import RayoIR
import RayoSema
import Testing

@Suite("Lowering expressions")
struct ExpressionLoweringTests {
    @Test func `an operand that is itself an operation is computed first, into a temporary`() throws(RejectedSource) {
        let main = try loweredMain("let x = 1 + 2 * 3")
        let expected = mainFunction(
            locals: [letLocal("x", .int), .temporary(.int)],
            block(
                declare(0),
                compute(1, .binary(.multiply(.checked), int(2), int(3))),
                compute(0, .binary(.add(.checked), int(1), read(1))),
                then: .return(nil),
            ),
        )
        #expect(main == expected)
    }

    @Test("a local used as an operand is read, and a local that gives a declaration its value is moved")
    func readsAndMoves() throws(RejectedSource) {
        let main = try loweredMain("let a = 1\nlet b = -a\nlet c = a")
        let expected = mainFunction(
            locals: [letLocal("a", .int), letLocal("b", .int), letLocal("c", .int)],
            block(
                declare(0), compute(0, .use(int(1))),
                declare(1), compute(1, .unary(.negate(.checked), read(0))),
                declare(2), compute(2, .use(move(0))),
                then: .return(nil),
            ),
        )
        #expect(main == expected)
    }

    @Test func `'!' applies to its operand as '-' does`() throws(RejectedSource) {
        let main = try loweredMain("let a = true\nlet b = !a")
        let expected = mainFunction(
            locals: [letLocal("a", .bool), letLocal("b", .bool)],
            block(
                declare(0), compute(0, .use(bool(true))),
                declare(1), compute(1, .unary(.not, read(0))),
                then: .return(nil),
            ),
        )
        #expect(main == expected)
    }

    @Test func `'copy' reads a local where a bare local would be moved`() throws(RejectedSource) {
        let main = try loweredMain("let a = 1\nlet b = copy a")
        let expected = mainFunction(
            locals: [letLocal("a", .int), letLocal("b", .int)],
            block(
                declare(0), compute(0, .use(int(1))),
                declare(1), compute(1, .use(read(0))),
                then: .return(nil),
            ),
        )
        #expect(main == expected)
    }

    @Test("'&&' evaluates its right operand in a block of its own, which only a true left operand reaches")
    func and() throws(RejectedSource) {
        let main = try loweredMain("let a = true\nlet b = a && false")
        let expected = mainFunction(
            locals: [letLocal("a", .bool), letLocal("b", .bool), .temporary(.bool)],
            block(
                declare(0), compute(0, .use(bool(true))),
                declare(1), compute(2, .use(read(0))),
                then: branch(read(2), then: 1, otherwise: 2),
            ),
            block(compute(2, .use(bool(false))), then: goto(2)),
            block(compute(1, .use(read(2))), then: .return(nil)),
        )
        #expect(main == expected)
    }

    @Test("'||' evaluates its right operand in a block of its own, which only a false left operand reaches")
    func or() throws(RejectedSource) {
        let main = try loweredMain("let a = true\nlet b = a || false")
        let expected = mainFunction(
            locals: [letLocal("a", .bool), letLocal("b", .bool), .temporary(.bool)],
            block(
                declare(0), compute(0, .use(bool(true))),
                declare(1), compute(2, .use(read(0))),
                then: branch(read(2), then: 2, otherwise: 1),
            ),
            block(compute(2, .use(bool(false))), then: goto(2)),
            block(compute(1, .use(read(2))), then: .return(nil)),
        )
        #expect(main == expected)
    }

    @Test("a '&&' that is the left operand of '||' is decided first, and its result decides whether '||' goes on")
    func andInsideOr() throws(RejectedSource) {
        let main = try loweredMain("let a = true\nlet b = false\nlet c = true\nlet d = a && b || c")
        let expected = mainFunction(
            locals: [
                letLocal("a", .bool), letLocal("b", .bool), letLocal("c", .bool), letLocal("d", .bool),
                .temporary(.bool), .temporary(.bool),
            ],
            // The `||`'s temporary is local 4 and the `&&`'s local 5; the `&&` starts with `a`.
            block(
                declare(0), compute(0, .use(bool(true))),
                declare(1), compute(1, .use(bool(false))),
                declare(2), compute(2, .use(bool(true))),
                declare(3), compute(5, .use(read(0))),
                then: branch(read(5), then: 1, otherwise: 2),
            ),
            // A true `a` goes on to `b`.
            block(compute(5, .use(read(1))), then: goto(2)),
            // The `&&`'s result starts the `||`'s, and only a false one goes on to `c`.
            block(compute(4, .use(read(5))), then: branch(read(4), then: 4, otherwise: 3)),
            block(compute(4, .use(read(2))), then: goto(4)),
            block(compute(3, .use(read(4))), then: .return(nil)),
        )
        #expect(main == expected)
    }

    @Test("a '||' that is the right operand of '&&' is lowered in the block that evaluates it, and joins before it")
    func orInsideAnd() throws(RejectedSource) {
        let main = try loweredMain("let a = true\nlet b = false\nlet c = true\nlet d = a && (b || c)")
        let expected = mainFunction(
            locals: [
                letLocal("a", .bool), letLocal("b", .bool), letLocal("c", .bool), letLocal("d", .bool),
                .temporary(.bool), .temporary(.bool),
            ],
            // The `&&`'s temporary is local 4 and the `||`'s local 5; the `&&` starts with `a`.
            block(
                declare(0), compute(0, .use(bool(true))),
                declare(1), compute(1, .use(bool(false))),
                declare(2), compute(2, .use(bool(true))),
                declare(3), compute(4, .use(read(0))),
                then: branch(read(4), then: 1, otherwise: 2),
            ),
            // A true `a` goes on to the `||`, which starts with `b`, and only a false `b` goes on to `c`.
            block(compute(5, .use(read(1))), then: branch(read(5), then: 4, otherwise: 3)),
            // The `&&`'s join.
            block(compute(3, .use(read(4))), then: .return(nil)),
            block(compute(5, .use(read(2))), then: goto(4)),
            // The `||`'s join, whose result is the `&&`'s, which goes on to the `&&`'s join.
            block(compute(4, .use(read(5))), then: goto(2)),
        )
        #expect(main == expected)
    }

    @Test func `a '||' that is a call's argument passes the temporary that holds its result`() throws(RejectedSource) {
        let program = try lowered("func main() {\nlet a = true\nshow(a || false)\n}\nfunc show(_ b: Bool) {}")
        let expected = mainFunction(
            locals: [letLocal("a", .bool), .temporary(.bool)],
            block(
                declare(0), compute(0, .use(bool(true))),
                compute(1, .use(read(0))),
                then: branch(read(1), then: 2, otherwise: 1),
            ),
            block(compute(1, .use(bool(false))), then: goto(2)),
            block(compute(nil, .call(.function(FunctionID(index: 1)), arguments: [read(1)])), then: .return(nil)),
        )
        #expect(program.body(at: 0) == expected)
    }
}
