import RayoIR
import RayoSema
import Testing

@Suite("Lowering statements")
struct StatementLoweringTests {
    @Test func `a declaration starts its local's life, then stores its value in it`() throws(RejectedSource) {
        let main = try loweredMain("let x = 1")
        let expected = mainFunction(
            locals: [letLocal("x", .int)],
            block(declare(0), compute(0, .use(int(1))), then: .return(nil)),
        )
        #expect(main == expected)
    }

    @Test func `an expression statement computes its value and keeps it nowhere`() throws(RejectedSource) {
        let main = try loweredMain("print(1 + 2)")
        let expected = mainFunction(
            locals: [.temporary(.int)],
            block(
                compute(0, .binary(.add, int(1), int(2))),
                compute(nil, .call(.printInt, arguments: [read(0)])),
                then: .return(nil),
            ),
        )
        #expect(main == expected)
    }

    @Test func `a declaration without a value only starts its local's life`() throws(RejectedSource) {
        let main = try loweredMain("var x: Int\nx = 1")
        let expected = mainFunction(
            locals: [varLocal("x", .int)],
            block(declare(0), compute(0, .use(int(1))), then: .return(nil)),
        )
        #expect(main == expected)
    }

    @Test func `an assignment stores its value in the local`() throws(RejectedSource) {
        let main = try loweredMain("var x = 1\nx = 2")
        let expected = mainFunction(
            locals: [varLocal("x", .int)],
            block(declare(0), compute(0, .use(int(1))), compute(0, .use(int(2))), then: .return(nil)),
        )
        #expect(main == expected)
    }

    @Test func `a compound assignment applies its operator to the local and the value`() throws(RejectedSource) {
        let main = try loweredMain("var x = 1\nx += 3")
        let expected = mainFunction(
            locals: [varLocal("x", .int)],
            block(declare(0), compute(0, .use(int(1))), compute(0, .binary(.add, read(0), int(3))), then: .return(nil)),
        )
        #expect(main == expected)
    }

    @Test("a compound assignment computes a value that is an operation into a temporary, then applies its operator")
    func compoundAssignOfOperation() throws(RejectedSource) {
        let main = try loweredMain("var x = 1\nx += 2 * 3")
        let expected = mainFunction(
            locals: [varLocal("x", .int), .temporary(.int)],
            block(
                declare(0), compute(0, .use(int(1))),
                compute(1, .binary(.multiply, int(2), int(3))),
                compute(0, .binary(.add, read(0), read(1))),
                then: .return(nil),
            ),
        )
        #expect(main == expected)
    }
}
