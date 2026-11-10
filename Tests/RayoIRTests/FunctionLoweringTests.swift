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
        #expect(program.functions[program.main.index] == expected)
    }

    @Test func `a function's parameters are its first locals, ahead of its temporaries`() throws(RejectedSource) {
        let double = try lowered("func main() {}\nfunc double(_ n: Int) -> Int { n * 2 }").functions[1]
        let expected = IRFunction(
            name: "double(_: Int)", parameterCount: 1, result: .int,
            locals: [parameter("n", .int), .temporary(.int)],
            blocks: [
                block(compute(1, .binary(.multiply, read(0), int(2))), then: .return(read(1))),
                block(then: .unreachable),
            ],
        )
        #expect(double == expected)
    }

    @Test func `a function returns a Bool result as it returns an Int one`() throws(RejectedSource) {
        let isZero = try lowered("func main() {}\nfunc isZero(_ n: Int) -> Bool { n == 0 }").functions[1]
        let expected = IRFunction(
            name: "isZero(_: Int)", parameterCount: 1, result: .bool,
            locals: [parameter("n", .int), .temporary(.bool)],
            blocks: [
                block(compute(1, .binary(.equal, read(0), int(0))), then: .return(read(1))),
                block(then: .unreachable),
            ],
        )
        #expect(isZero == expected)
    }

    @Test func `a 'return' of a local moves its value out as the result`() throws(RejectedSource) {
        let seven = try lowered("func main() {}\nfunc seven() -> Int {\nlet x = 7\nreturn x\n}").functions[1]
        let expected = IRFunction(
            name: "seven()", parameterCount: 0, result: .int,
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
            block(compute(nil, .call(.printInt, arguments: [int(1)])), then: .return(nil)),
            block(then: .return(nil)),
        )
        #expect(main == expected)
    }
}
