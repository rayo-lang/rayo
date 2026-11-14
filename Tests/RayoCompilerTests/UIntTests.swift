import Testing
import RayoDiagnostics

struct UIntTests {
    @Test(arguments: [
        "let u: UInt = 5\nprint(u)",
        "print(takes(5))",
        "print(gives())",
        "var u: UInt\nu = 18446744073709551615\nprint(u)",
        "let u: UInt = 1\nprint(u + 2)",
        "let u: UInt = 1\nprint(2 * u)",
        "let u: UInt = 1\nprint(u < 2)",
        "let u: UInt = 1\nprint(u == 18446744073709551615)",
        "let u: UInt = 0\nprint(-u)",
        "let u: UInt = -0\nprint(u)",
        "let h = Hits(count: 3)\nprint(takes(copy h.count))",
        "var u: UInt = 1\nu += 2\nprint(u)",
        "let u: UInt = 1\nprint(u + (1 + 18446744073709551614))",
    ])
    func `a literal is a UInt where its position expects one`(body: String) {
        let source = mainSource(body) + """

            struct Hits(var count: UInt)
            func takes(_ u: UInt) -> UInt { copy u }
            func gives() -> UInt { return 18446744073709551615 }
            """
        #expect(errors(source) == [])
    }

    @Test func `a literal that 'print' takes is an Int, as a generic function's literal argument defaults to one`() {
        let source = mainSource("print(18446744073709551615)")
        #expect(errors(source) == [.literalDoesntFit(type: "Int")])
    }

    @Test(arguments: [("f(1)", [ErrorCode.ambiguousCall(name: "f")]), ("let u: UInt = 1\nf(u)", [])])
    func `a literal passed to overloads on Int and UInt makes the call ambiguous`(
        body: String, expected: [ErrorCode],
    ) {
        let source = mainSource(body) + "\nfunc f(_ i: Int) {}\nfunc f(_ u: UInt) {}"
        #expect(errors(source) == expected)
        #expect(ErrorCode.ambiguousCall(name: "f").message == "the call fits more than one 'f'")
    }

    @Test func `a literal with no position to type it is an Int`() {
        #expect(errors(mainSource("let x = 5\nlet u: UInt = x")) == [.typeMismatch(expected: "UInt", found: "Int")])
    }

    @Test(arguments: [
        ("let u: UInt = -1", "-1"),
        ("let u: UInt = 2\nprint(u + -1)", "-1"),
        ("let u: UInt = 3 - -1", "-1"),
    ])
    func `a negative literal doesn't fit in a UInt`(body: String, literal: String) {
        let (codes, covered) = codesAndCoverage(inMain: body)
        #expect(codes == [.literalDoesntFit(type: "UInt")])
        #expect(covered == [literal])
        #expect(ErrorCode.literalDoesntFit(type: "UInt").message == "the literal doesn't fit in a UInt")
    }

    @Test func `a literal above UInt.max doesn't fit in 64 bits`() {
        #expect(errors(mainSource("let u: UInt = 18446744073709551616")) == [.literalExceeds64Bits])
    }

    @Test(arguments: ["+", "-", "*", "/", "%", "<", "<=", ">", ">=", "==", "!="])
    func `an operator on an Int and a UInt is reported, since neither converts to the other`(op: String) {
        let (codes, covered) = codesAndCoverage(inMain: "let i = 1\nlet u: UInt = 1\nlet x = i \(op) u")
        #expect(codes == [.operandsDiffer(op: op, left: "Int", right: "UInt")])
        #expect(covered == ["i \(op) u"])
    }

    @Test func `an Int and a UInt that differ name both types`() {
        let message = ErrorCode.operandsDiffer(op: "+", left: "Int", right: "UInt").message
        #expect(message == "'+' needs operands of one type, found Int and UInt")
    }

    @Test func `arithmetic on values that aren't integers says so`() {
        #expect(ErrorCode.integerOperands(op: "+", left: "Bool", right: "Int").message ==
            "'+' needs integer operands, found Bool and Int")
        #expect(ErrorCode.integerOperand(op: "-", found: "Bool").message == "'-' needs an integer operand, found Bool")
    }

    @Test(arguments: [
        "let i = -1\nprint(UInt(i))",
        "let u: UInt = 1\nlet i: Int = Int(u)\nprint(i)",
    ])
    func `'UInt(_:)' converts an Int, and 'Int(_:)' a UInt`(body: String) {
        #expect(errors(mainSource(body)) == [])
    }

    @Test(arguments: [
        "print(UInt(18446744073709551615))",
        "let u: UInt = UInt(5)\nprint(u)",
        "let i: Int = Int(-9223372036854775808)\nprint(i)",
    ])
    func `'UInt' or 'Int' called with one literal makes the literal a value of its type`(body: String) {
        #expect(errors(mainSource(body)) == [])
    }

    @Test(arguments: [
        ("let u = UInt(-1)", ErrorCode.literalDoesntFit(type: "UInt"), "-1"),
        ("let i = Int(18446744073709551615)", .literalDoesntFit(type: "Int"), "18446744073709551615"),
    ])
    func `a literal that 'UInt' or 'Int' is called with must fit in its type`(
        body: String, expected: ErrorCode, literal: String,
    ) {
        let (codes, covered) = codesAndCoverage(inMain: body)
        #expect(codes == [expected])
        #expect(covered == [literal])
    }

    @Test(arguments: [
        ("let u: UInt = 1\nprint(UInt(u))", ErrorCode.typeMismatch(expected: "Int", found: "UInt")),
        ("let i = 1\nprint(Int(i))", .typeMismatch(expected: "UInt", found: "Int")),
    ])
    func `a conversion takes the other integer type`(body: String, expected: ErrorCode) {
        #expect(errors(mainSource(body)) == [expected])
    }
}
