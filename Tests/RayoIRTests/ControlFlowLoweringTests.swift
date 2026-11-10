import RayoIR
import RayoSema
import Testing

@Suite("Lowering branches and loops")
struct ControlFlowLoweringTests {
    @Test("an 'if' branches to a block for each branch, and both go on to a block after them")
    func ifElse() throws {
        let main = try loweredMain("let c = true\nif c { print(1) } else { print(2) }")
        #expect(main.blocks == [
            block(declare(0), compute(0, .use(bool(true))), then: branch(read(0), then: 1, otherwise: 2)),
            block(compute(nil, .call(.printInt, arguments: [int(1)])), then: goto(3)),
            block(compute(nil, .call(.printInt, arguments: [int(2)])), then: goto(3)),
            block(then: .return(nil)),
        ])
    }

    @Test("an 'if' without 'else' branches to an empty block where its condition fails")
    func ifWithoutElse() throws {
        let main = try loweredMain("let c = true\nif c { print(1) }")
        #expect(main.blocks == [
            block(declare(0), compute(0, .use(bool(true))), then: branch(read(0), then: 1, otherwise: 2)),
            block(compute(nil, .call(.printInt, arguments: [int(1)])), then: goto(3)),
            block(then: goto(3)),
            block(then: .return(nil)),
        ])
    }

    @Test("a 'while' tests its condition in a header, whose body goes back to it, and whose exit goes on")
    func whileLoop() throws {
        let main = try loweredMain("var i = 0\nwhile i < 3 { i += 1 }")
        #expect(main.locals == [.source(name: "i", kind: .var, type: .int), .temporary(.bool)])
        #expect(main.blocks == [
            block(declare(0), compute(0, .use(int(0))), then: goto(1)),
            block(compute(1, .binary(.less, read(0), int(3))), then: branch(read(1), then: 2, otherwise: 3)),
            block(compute(0, .binary(.add, read(0), int(1))), then: goto(1)),
            block(then: .return(nil)),
        ])
    }

    @Test("a 'while true' header goes straight to its body, and a 'break' goes to the exit")
    func whileTrue() throws {
        let main = try loweredMain("while true { break }")
        #expect(main.blocks == [
            block(then: goto(1)),
            block(then: goto(2)),
            block(then: goto(3)),
            block(then: .return(nil)),
            // The code after the `break`, which no path reaches, goes back to the header.
            block(then: goto(1)),
        ])
    }

    @Test("a 'continue' goes back to the header")
    func continueLoop() throws {
        let main = try loweredMain("var i = 0\nwhile i < 2 {\ni += 1\ncontinue\n}")
        #expect(main.blocks == [
            block(declare(0), compute(0, .use(int(0))), then: goto(1)),
            block(compute(1, .binary(.less, read(0), int(2))), then: branch(read(1), then: 2, otherwise: 3)),
            block(compute(0, .binary(.add, read(0), int(1))), then: goto(1)),
            block(then: .return(nil)),
            block(then: goto(1)),
        ])
    }

    @Test("'break' leaves the innermost loop")
    func nestedBreak() throws {
        let main = try loweredMain("while true {\nwhile true { break }\nbreak\n}")
        #expect(main.blocks == [
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
            block(then: goto(4)),
            block(then: goto(1)),
        ])
    }

    @Test("a 'return' leaves the function, and the code after it goes in a block of its own")
    func returnFromVoid() throws {
        let main = try loweredMain("print(1)\nreturn\nprint(2)")
        #expect(main.blocks == [
            block(compute(nil, .call(.printInt, arguments: [int(1)])), then: .return(nil)),
            block(compute(nil, .call(.printInt, arguments: [int(2)])), then: .return(nil)),
        ])
    }
}
