import RayoIR
import RayoSema
import Testing

@Suite("Lowering functions")
struct FunctionLoweringTests {
    @Test func `a call names the function it calls, and passes its arguments as operands`() throws(RejectedSource) {
        let program = try lowered("func main() {\nlet x = double(3)\n}\nfunc double(_ n: Int) -> Int { n * 2 }")
        let expected = mainFunction(
            locals: [letLocal("x", .int)],
            block(
                declare(0), compute(0, .call(.function(FunctionID(index: 1)), arguments: [int(3)])),
                then: .return(nil),
            ),
        )
        // The source declares `main`, so the program has one.
        #expect(program.body(at: program.main!.index) == expected)
    }

    @Test func `the program's table declares each function, by its ID in source order`() throws(RejectedSource) {
        let program = try lowered("func main() {}\nfunc double(_ n: Int, by: Bool) -> Int { n * 2 }")
        #expect(program.functions.ids == [FunctionID(index: 0), FunctionID(index: 1)])
        #expect(program.functions[FunctionID(index: 0)] ==
            FunctionDeclaration(name: "main()", parameters: [], result: .void, kind: .written))
        let double = FunctionDeclaration(name: "double(_: Int, by: Bool)", parameters: [.int, .bool], result: .int,
                                         kind: .written)
        #expect(program.functions[FunctionID(index: 1)] == double)
    }

    @Test func `a function without a body keeps its ID, and leaves no gap among the bodies`() {
        // Declare a function that has no body, and a `main` after it that has one.
        var functions = FunctionTable()
        let declaration = FunctionDeclaration(name: "f()", parameters: [], result: .void, kind: .written)
        let bodiless = functions.declare(declaration)
        let main = functions.declare(FunctionDeclaration(name: "main()", parameters: [], result: .void, kind: .written))
        let checked = CheckedProgram(types: .empty, functions: functions,
                                     bodies: [main: CheckedBody(locals: [], statements: [])], main: main)

        // Lowering keeps both declarations and their IDs, and lowers the one body there is.
        let program = Lowering.lower(checked)
        #expect([bodiless, main] == [FunctionID(index: 0), FunctionID(index: 1)])
        #expect(program.functions == functions)
        #expect(program.bodies == [main: mainFunction(block(then: .return(nil)))])
        #expect(program.definedFunctions.map(\.id) == [main])
    }

    @Test func `a function's parameters are its first locals, ahead of its temporaries`() throws(RejectedSource) {
        let double = try lowered("func main() {}\nfunc double(_ n: Int) -> Int { n * 2 }").body(at: 1)
        let expected = IRBody(
            locals: [parameter("n", .int), .temporary(.int)],
            blocks: [
                block(compute(1, .binary(.multiply, read(0), int(2))), then: .return(read(1))),
                block(then: .unreachable),
            ],
        )
        #expect(double == expected)
    }

    @Test func `a function returns a Bool result as it returns an Int one`() throws(RejectedSource) {
        let isZero = try lowered("func main() {}\nfunc isZero(_ n: Int) -> Bool { n == 0 }").body(at: 1)
        let expected = IRBody(
            locals: [parameter("n", .int), .temporary(.bool)],
            blocks: [
                block(compute(1, .binary(.equal, read(0), int(0))), then: .return(read(1))),
                block(then: .unreachable),
            ],
        )
        #expect(isZero == expected)
    }

    @Test func `a 'return' of a local moves its value out as the result`() throws(RejectedSource) {
        let seven = try lowered("func main() {}\nfunc seven() -> Int {\nlet x = 7\nreturn x\n}").body(at: 1)
        let expected = IRBody(
            locals: [letLocal("x", .int)],
            blocks: [
                block(declare(0), compute(0, .use(int(7))), then: .return(move(0))),
                block(then: .unreachable),
            ],
        )
        #expect(seven == expected)
    }

    @Test func `a 'return' of a Void value computes it, and returns nothing`() throws(RejectedSource) {
        let main = try loweredMain("return print(1)")
        let expected = mainFunction(
            block(compute(nil, .call(.builtin(.printInt), arguments: [int(1)])), then: .return(nil)),
            block(then: .return(nil)),
        )
        #expect(main == expected)
    }
}
