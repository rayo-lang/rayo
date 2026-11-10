import RayoIR
import RayoSema
import Testing

@Suite("Lowering expressions")
struct ExpressionLoweringTests {
    @Test("a declaration starts its local's life, then stores its value in it")
    func declaration() throws {
        let main = try loweredMain("let x = 1")
        #expect(main.locals == [.source(name: "x", kind: .let, type: .int)])
        #expect(main.blocks == [block(declare(0), compute(0, .use(int(1))), then: .return(nil))])
    }

    @Test("an operand that is itself an operation is computed first, into a temporary")
    func nestedOperation() throws {
        let main = try loweredMain("let x = 1 + 2 * 3")
        #expect(main.locals == [.source(name: "x", kind: .let, type: .int), .temporary(.int)])
        #expect(main.blocks == [block(
            declare(0),
            compute(1, .binary(.multiply, int(2), int(3))),
            compute(0, .binary(.add, int(1), read(1))),
            then: .return(nil))])
    }

    @Test("a local used as an operand is read, and a local that gives a declaration its value is moved")
    func readsAndMoves() throws {
        let main = try loweredMain("let a = 1\nlet b = -a\nlet c = a")
        #expect(main.blocks == [block(
            declare(0), compute(0, .use(int(1))),
            declare(1), compute(1, .unary(.negate, read(0))),
            declare(2), compute(2, .use(move(0))),
            then: .return(nil))])
    }

    @Test("'copy' reads a local where a bare local would be moved")
    func copy() throws {
        let main = try loweredMain("let a = 1\nlet b = copy a")
        #expect(main.blocks == [block(
            declare(0), compute(0, .use(int(1))),
            declare(1), compute(1, .use(read(0))),
            then: .return(nil))])
    }

    @Test("an expression statement computes its value and keeps it nowhere")
    func expressionStatement() throws {
        let main = try loweredMain("print(1 + 2)")
        #expect(main.locals == [.temporary(.int)])
        #expect(main.blocks == [block(
            compute(0, .binary(.add, int(1), int(2))),
            compute(nil, .call(.printInt, arguments: [read(0)])),
            then: .return(nil))])
    }

    @Test("an assignment stores its value in the local, and a compound one applies its operator to the local first")
    func assignments() throws {
        let main = try loweredMain("var x = 1\nx = 2\nx += 3")
        #expect(main.locals == [.source(name: "x", kind: .var, type: .int)])
        #expect(main.blocks == [block(
            declare(0), compute(0, .use(int(1))),
            compute(0, .use(int(2))),
            compute(0, .binary(.add, read(0), int(3))),
            then: .return(nil))])
    }

    @Test("'&&' evaluates its right operand in a block of its own, which only a true left operand reaches")
    func and() throws {
        let main = try loweredMain("let a = true\nlet b = a && false")
        #expect(main.locals == [
            .source(name: "a", kind: .let, type: .bool), .source(name: "b", kind: .let, type: .bool),
            .temporary(.bool),
        ])
        #expect(main.blocks == [
            block(
                declare(0), compute(0, .use(bool(true))),
                declare(1), compute(2, .use(read(0))),
                then: branch(read(2), then: 1, otherwise: 2)),
            block(compute(2, .use(bool(false))), then: goto(2)),
            block(compute(1, .use(read(2))), then: .return(nil)),
        ])
    }

    @Test("'||' evaluates its right operand in a block of its own, which only a false left operand reaches")
    func or() throws {
        let main = try loweredMain("let a = true\nlet b = a || false")
        #expect(main.blocks == [
            block(
                declare(0), compute(0, .use(bool(true))),
                declare(1), compute(2, .use(read(0))),
                then: branch(read(2), then: 2, otherwise: 1)),
            block(compute(2, .use(bool(false))), then: goto(2)),
            block(compute(1, .use(read(2))), then: .return(nil)),
        ])
    }
}
