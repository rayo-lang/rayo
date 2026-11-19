import RayoCheckedProgram
import RayoIR
import Testing

/// IR that uses a local on some path after a retirement ends its life, and what the verifier says is wrong with it.
struct RetiredUse: CustomTestStringConvertible, Sendable {
    let testDescription: String
    /// The blocks of `main`, as text, after it declares and assigns its three locals.
    let blocks: String
    let message: String
}

@Suite("Verifying where each local lives")
struct LocalLifeTests {
    @Test(arguments: retiredUses)
    func `a use of a local on a path after its retirement is a violation that names the local and the block`(
        use: RetiredUse,
    ) throws {
        let program = try IRParser.program(from: assigningThreeLocals(use.blocks))
        let violation = IRViolation(function: "main()", message: use.message)
        #expect(IRVerifier.verify(program, from: .ownership) == violation)
    }

    @Test func `a local declared again after its retirement may be used, and retired again`() throws {
        let program = try IRParser.program(from: assigningThreeLocals("""
              _ = call builtin "print(_: Int)"(read %0 @1:1-1:2) @1:1-1:2
              retire %0
              goto bb1
            bb1:
              declare %0
              %0 @1:1-1:2 = operand 2 @1:1-1:2
              _ = call builtin "print(_: Int)"(read %0 @1:1-1:2) @1:1-1:2
              retire %0
              goto bb1
            """))
        #expect(IRVerifier.verify(program, from: .ownership) == nil)
    }
}

private let retiredUses = [
    RetiredUse(
        testDescription: "a use after a retirement in the same block",
        blocks: """
              retire %0
              _ = call builtin "print(_: Int)"(read %0 @1:1-1:2) @1:1-1:2
              return
            """,
        message: "the IR uses %0 at bb0, where it is retired",
    ),
    RetiredUse(
        testDescription: "a use where one of the paths that join retired the local",
        blocks: """
              branch true, bb1, bb2
            bb1:
              retire %0
              goto bb2
            bb2:
              _ = call builtin "print(_: Int)"(read %0 @1:1-1:2) @1:1-1:2
              return
            """,
        message: "the IR uses %0 at bb2, where it is retired",
    ),
    RetiredUse(
        testDescription: "a use that a loop's next pass reaches after the retirement",
        blocks: """
              goto bb1
            bb1:
              _ = call builtin "print(_: Int)"(read %0 @1:1-1:2) @1:1-1:2
              retire %0
              goto bb1
            """,
        message: "the IR uses %0 at bb1, where it is retired",
    ),
    RetiredUse(
        testDescription: "an index that a retired local holds",
        blocks: """
              retire %1
              %2[%1] @1:1-1:2 = operand 3 @1:1-1:2
              return
            """,
        message: "the IR uses %1 at bb0, where it is retired",
    ),
]

/// A program whose `main` declares and assigns its Int local `%0`, its UInt local `%1` and its array `%2`, then runs
/// `blocks`.
private func assigningThreeLocals(_ blocks: String) -> String {
    """
    main "main()"
    func "main()"() -> Void {
      temp %0: Int
      temp %1: UInt
      temp %2: [2 of Int]
    bb0:
      declare %0
      %0 @1:1-1:2 = operand 1 @1:1-1:2
      declare %1
      %1 @1:1-1:2 = index UInt 1 below 2 @1:1-1:2
      declare %2
      %2 @1:1-1:2 = fill 2 of 0 @1:1-1:2
    \(blocks)
    }
    """
}
