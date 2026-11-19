import RayoIR
import Testing

/// IR in which a path from the entry reaches a block that ends in `unreachable`, and the block the verifier names.
struct ReachedUnreachable: CustomTestStringConvertible, Sendable {
    let testDescription: String
    /// The blocks of `main`, as text.
    let blocks: String
    /// The block that ends in `unreachable` and that a path reaches.
    let block: Int
}

@Suite("Verifying that no path reaches an 'unreachable'")
struct UnreachableBlockTests {
    @Test(arguments: reachedUnreachables, [IRStage.lowering, .ownership])
    func `a block that a path reaches and that ends in 'unreachable' is a violation that names the block`(
        reached: ReachedUnreachable, stage: IRStage,
    ) throws {
        let program = try IRParser.program(from: main(reached.blocks))
        let message = "the IR reaches bb\(reached.block), which ends in unreachable"
        let violation = IRViolation(function: "main()", message: message)
        #expect(IRVerifier.verify(program, from: stage) == violation)
    }

    @Test(arguments: [IRStage.lowering, .ownership])
    func `a block that no path reaches may end in 'unreachable'`(stage: IRStage) throws {
        // `bb1` follows a return, and `bb3` only goes to itself and to `bb1`.
        let program = try IRParser.program(from: main("""
              goto bb2
            bb1:
              unreachable
            bb2:
              return
            bb3:
              branch true, bb3, bb1
            """))
        #expect(IRVerifier.verify(program, from: stage) == nil)
    }
}

private let reachedUnreachables = [
    ReachedUnreachable(testDescription: "the entry", blocks: "  unreachable", block: 0),
    ReachedUnreachable(
        testDescription: "a branch's other block, though the branch tests a constant",
        blocks: """
              branch true, bb1, bb2
            bb1:
              return
            bb2:
              unreachable
            """,
        block: 2,
    ),
    ReachedUnreachable(
        testDescription: "a block that a loop's exit goes to",
        blocks: """
              goto bb1
            bb1:
              branch false, bb2, bb3
            bb2:
              goto bb1
            bb3:
              unreachable
            """,
        block: 3,
    ),
]

/// A program whose `main`, which takes and returns nothing, runs `blocks`.
private func main(_ blocks: String) -> String {
    """
    main "main()"
    func "main()"() -> Void {
    bb0:
    \(blocks)
    }
    """
}
