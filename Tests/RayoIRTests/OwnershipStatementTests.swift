import RayoIR
import Testing

/// IR that holds a statement only the ownership stage writes, and what the verifier says is wrong with it as lowering's
/// IR.
struct OwnershipStatement: CustomTestStringConvertible, Sendable {
    let testDescription: String
    /// The blocks of `main`, as text, after it declares and assigns its Int local `%0`.
    let blocks: String
    let message: String
}

@Suite("Verifying that lowering's IR holds only the statements lowering writes")
struct OwnershipStatementTests {
    @Test(arguments: ownershipStatements)
    func `an end or a retirement in lowering's IR is a violation that names the statement and the block`(
        statement: OwnershipStatement,
    ) throws {
        let program = try IRParser.program(from: assigningALocal(statement.blocks))
        let violation = IRViolation(function: "main()", message: statement.message)
        #expect(IRVerifier.verify(program, from: .lowering) == violation)
    }

    @Test(arguments: ownershipStatements)
    func `an end or a retirement in the ownership stage's IR is no violation`(statement: OwnershipStatement) throws {
        let program = try IRParser.program(from: assigningALocal(statement.blocks))
        #expect(IRVerifier.verify(program, from: .ownership) == nil)
    }
}

private let ownershipStatements = [
    OwnershipStatement(
        testDescription: "an end of an access",
        blocks: """
              goto bb1
            bb1:
              begin a0 read %0 @1:1-1:2
              _ = call "show(_: &Int)"(a0) @1:1-1:2
              end a0
              return
            """,
        message: "the IR ends a0 at bb1, though only the ownership stage ends an access",
    ),
    OwnershipStatement(
        testDescription: "a retirement of a local",
        blocks: """
              _ = call builtin "print(_: Int)"(read %0 @1:1-1:2) @1:1-1:2
              goto bb1
            bb1:
              retire %0
              return
            """,
        message: "the IR retires %0 at bb1, though only the ownership stage retires a local",
    ),
]

/// A program whose `main` declares and assigns its Int local `%0`, then runs `blocks`, which may call `show`, a
/// function that borrows an Int.
private func assigningALocal(_ blocks: String) -> String {
    """
    main "main()"
    func "show(_: &Int)"(_: Int) -> Void
    func "main()"() -> Void {
      temp %0: Int
    bb0:
      declare %0
      %0 @1:1-1:2 = operand 1 @1:1-1:2
    \(blocks)
    }
    """
}
