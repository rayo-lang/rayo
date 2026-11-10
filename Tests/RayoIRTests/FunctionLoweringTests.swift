import RayoIR
import RayoSema
import RayoSource
import Testing

@Suite("Lowering functions")
struct FunctionLoweringTests {
    @Test("a call names the function it calls, and passes its arguments as operands")
    func call() throws {
        let program = try lowered("func main() {\nlet x = double(3)\n}\nfunc double(_ n: Int) -> Int { n * 2 }")
        #expect(program.main == FunctionID(index: 0))
        #expect(program.functions[0].blocks == [block(
            declare(0), compute(0, .call(.function(FunctionID(index: 1)), arguments: [int(3)])),
            then: .return(nil))])
    }

    @Test("a function's parameters are its first locals, and the end of a function with a result is unreachable")
    func parametersAndResult() throws {
        let double = try lowered("func main() {}\nfunc double(_ n: Int) -> Int { n * 2 }").functions[1]
        #expect(double.parameterCount == 1)
        #expect(double.result == .int)
        #expect(double.locals == [.source(name: "n", kind: .parameter, type: .int), .temporary(.int)])
        #expect(double.blocks == [
            block(compute(1, .binary(.multiply, read(0), int(2))), then: .return(read(1))),
            block(then: .unreachable),
        ])
    }

    @Test("a function returns a Bool result as it returns an Int one")
    func boolResult() throws {
        let isZero = try lowered("func main() {}\nfunc isZero(_ n: Int) -> Bool { n == 0 }").functions[1]
        #expect(isZero.blocks == [
            block(compute(1, .binary(.equal, read(0), int(0))), then: .return(read(1))),
            block(then: .unreachable),
        ])
    }

    @Test("a 'return' of a Void value computes it, and returns nothing")
    func returnVoidValue() throws {
        let main = try loweredMain("return print(1)")
        #expect(main.blocks == [
            block(compute(nil, .call(.printInt, arguments: [int(1)])), then: .return(nil)),
            block(then: .return(nil)),
        ])
    }

    @Test("an operation keeps the range of the expression it computes, and an operand the range of its local")
    func ranges() throws {
        let source = "func main() {\n    let a = 7\n    print(a / 0)\n}"
        let main = try loweredWithRanges(source).functions[0]

        // The division is computed into a temporary, and the call reads it.
        guard case .compute(_, .binary(.divide, let dividend, _), let range) = main.blocks[0].statements[2],
              case .read(let place) = dividend else {
            Issue.record("the division isn't the third statement of \(main.blocks[0])")
            return
        }
        #expect(text(of: range, in: source) == "a / 0")
        #expect(text(of: place.range, in: source) == "a")
    }
}

/// The text of `source` that `range` covers.
private func text(of range: SourceRange, in source: String) -> String {
    let bytes = Array(source.utf8)[range.start.offset..<range.end.offset]
    return String(decoding: bytes, as: UTF8.self)
}
