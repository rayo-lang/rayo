import RayoIR
import RayoSema
import Testing

@Suite("Lowering expressions")
struct ExpressionLoweringTests {
    @Test("a declaration starts its local's life, then stores its value in it")
    func declaration() throws {
        let main = try loweredMain("let x = 1")
        #expect(main == mainFunction(
            locals: [letLocal("x", .int)],
            block(declare(0), compute(0, .use(int(1))), then: .return(nil))))
    }

    @Test("an operand that is itself an operation is computed first, into a temporary")
    func nestedOperation() throws {
        let main = try loweredMain("let x = 1 + 2 * 3")
        #expect(main == mainFunction(
            locals: [letLocal("x", .int), .temporary(.int)],
            block(
                declare(0),
                compute(1, .binary(.multiply, int(2), int(3))),
                compute(0, .binary(.add, int(1), read(1))),
                then: .return(nil))))
    }

    @Test("a local used as an operand is read, and a local that gives a declaration its value is moved")
    func readsAndMoves() throws {
        let main = try loweredMain("let a = 1\nlet b = -a\nlet c = a")
        #expect(main == mainFunction(
            locals: [letLocal("a", .int), letLocal("b", .int), letLocal("c", .int)],
            block(
                declare(0), compute(0, .use(int(1))),
                declare(1), compute(1, .unary(.negate, read(0))),
                declare(2), compute(2, .use(move(0))),
                then: .return(nil))))
    }

    @Test("'!' applies to its operand as '-' does")
    func not() throws {
        let main = try loweredMain("let a = true\nlet b = !a")
        #expect(main == mainFunction(
            locals: [letLocal("a", .bool), letLocal("b", .bool)],
            block(
                declare(0), compute(0, .use(bool(true))),
                declare(1), compute(1, .unary(.not, read(0))),
                then: .return(nil))))
    }

    @Test("'copy' reads a local where a bare local would be moved")
    func copy() throws {
        let main = try loweredMain("let a = 1\nlet b = copy a")
        #expect(main == mainFunction(
            locals: [letLocal("a", .int), letLocal("b", .int)],
            block(
                declare(0), compute(0, .use(int(1))),
                declare(1), compute(1, .use(read(0))),
                then: .return(nil))))
    }

    @Test("an expression statement computes its value and keeps it nowhere")
    func expressionStatement() throws {
        let main = try loweredMain("print(1 + 2)")
        #expect(main == mainFunction(
            locals: [.temporary(.int)],
            block(
                compute(0, .binary(.add, int(1), int(2))),
                compute(nil, .call(.printInt, arguments: [read(0)])),
                then: .return(nil))))
    }

    @Test("an assignment stores its value in the local, and a compound one applies its operator to the local first")
    func assignments() throws {
        let main = try loweredMain("var x = 1\nx = 2\nx += 3")
        #expect(main == mainFunction(
            locals: [varLocal("x", .int)],
            block(
                declare(0), compute(0, .use(int(1))),
                compute(0, .use(int(2))),
                compute(0, .binary(.add, read(0), int(3))),
                then: .return(nil))))
    }

    @Test("a compound assignment computes a value that is an operation into a temporary, then applies its operator")
    func compoundAssignOfOperation() throws {
        let main = try loweredMain("var x = 1\nx += 2 * 3")
        #expect(main == mainFunction(
            locals: [varLocal("x", .int), .temporary(.int)],
            block(
                declare(0), compute(0, .use(int(1))),
                compute(1, .binary(.multiply, int(2), int(3))),
                compute(0, .binary(.add, read(0), read(1))),
                then: .return(nil))))
    }

    @Test("'&&' evaluates its right operand in a block of its own, which only a true left operand reaches")
    func and() throws {
        let main = try loweredMain("let a = true\nlet b = a && false")
        #expect(main == mainFunction(
            locals: [letLocal("a", .bool), letLocal("b", .bool), .temporary(.bool)],
            block(
                declare(0), compute(0, .use(bool(true))),
                declare(1), compute(2, .use(read(0))),
                then: branch(read(2), then: 1, otherwise: 2)),
            block(compute(2, .use(bool(false))), then: goto(2)),
            block(compute(1, .use(read(2))), then: .return(nil))))
    }

    @Test("'||' evaluates its right operand in a block of its own, which only a false left operand reaches")
    func or() throws {
        let main = try loweredMain("let a = true\nlet b = a || false")
        #expect(main == mainFunction(
            locals: [letLocal("a", .bool), letLocal("b", .bool), .temporary(.bool)],
            block(
                declare(0), compute(0, .use(bool(true))),
                declare(1), compute(2, .use(read(0))),
                then: branch(read(2), then: 2, otherwise: 1)),
            block(compute(2, .use(bool(false))), then: goto(2)),
            block(compute(1, .use(read(2))), then: .return(nil))))
    }

    @Test("a '&&' that is the left operand of '||' is decided first, and its result decides whether '||' goes on")
    func andInsideOr() throws {
        let main = try loweredMain("let a = true\nlet b = false\nlet c = true\nlet d = a && b || c")
        #expect(main == mainFunction(
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
                then: branch(read(5), then: 1, otherwise: 2)),
            // A true `a` goes on to `b`.
            block(compute(5, .use(read(1))), then: goto(2)),
            // The `&&`'s result starts the `||`'s, and only a false one goes on to `c`.
            block(compute(4, .use(read(5))), then: branch(read(4), then: 4, otherwise: 3)),
            block(compute(4, .use(read(2))), then: goto(4)),
            block(compute(3, .use(read(4))), then: .return(nil))))
    }

    @Test("a '||' that is a call's argument passes the temporary that holds its result")
    func orAsArgument() throws {
        let program = try lowered("func main() {\nlet a = true\nshow(a || false)\n}\nfunc show(_ b: Bool) {}")
        #expect(program.functions[0] == mainFunction(
            locals: [letLocal("a", .bool), .temporary(.bool)],
            block(
                declare(0), compute(0, .use(bool(true))),
                compute(1, .use(read(0))),
                then: branch(read(1), then: 2, otherwise: 1)),
            block(compute(1, .use(bool(false))), then: goto(2)),
            block(compute(nil, .call(.function(FunctionID(index: 1)), arguments: [read(1)])), then: .return(nil))))
    }
}
