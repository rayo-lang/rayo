import RayoCheckedProgram
@testable import RayoIR
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
        #expect(try verify(program, from: .ownership) == violation)
    }

    @Test func `a local declared again after its retirement may be used, and retired again`() throws {
        let program = try IRParser.program(from: assigningThreeLocals("""
              begin a0 read %0 @1:1-1:2
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:2
              end a0
              retire %0
              goto bb1
            bb1:
              declare %0
              %0 @1:1-1:2 = operand 2 @1:1-1:2
              begin a1 read %0 @1:1-1:2
              _ = call builtin "print(_: &Int)"(a1) @1:1-1:2
              end a1
              retire %0
              goto bb1
            """))
        #expect(try verify(program, from: .ownership) == nil)
    }

    @Test func `a block that no path reaches may use a retired local, since it never runs`() throws {
        let program = try IRParser.program(from: assigningThreeLocals("""
              return
            bb1:
              retire %0
              begin a0 read %0 @1:1-1:2
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:2
              end a0
              return
            """))
        #expect(try verify(program, from: .ownership) == nil)
    }

    @Test func `loops in a row that each retire their own locals as they end use no retired local`() throws {
        let program = try IRParser.program(from: retiringLoops(3))
        #expect(try verify(program, from: .ownership) == nil)
    }
}

/// A program whose `main` runs `loops` loops in a row, each with locals of its own that it retires as it ends.
private func retiringLoops(_ loops: Int) -> String {
    let locals = (0..<loops).map { loop in
        """
          var %\(3 * loop) c\(loop): UInt @1:1-1:1
          temp %\(3 * loop + 1): Bool
          let %\(3 * loop + 2) v\(loop): Int @1:1-1:1
        """
    }
    let blocks = (0..<loops).map { loop in
        let (counter, test, value) = (3 * loop, 3 * loop + 1, 3 * loop + 2)
        let (start, header, body) = (3 * loop, 3 * loop + 1, 3 * loop + 2)
        return """
            bb\(start):
            \(retiringLoop(loop - 1))
              declare %\(counter)
              %\(counter) @1:1-1:1 = operand UInt 0 @1:1-1:1
              goto bb\(header)
            bb\(header):
              declare %\(test)
              %\(test) @1:1-1:1 = less read %\(counter) @1:1-1:1, UInt 8 @1:1-1:1
              branch read %\(test) @1:1-1:1, bb\(body), bb\(start + 3)
            bb\(body):
              retire %\(test)
              declare %\(value)
              %\(value) @1:1-1:1 = call builtin "Int(_: UInt)"(read %\(counter) @1:1-1:1) @1:1-1:1
              begin a\(loop) read %\(value) @1:1-1:1
              _ = call builtin "print(_: &Int)"(a\(loop)) @1:1-1:1
              end a\(loop)
              retire %\(value)
              %\(counter) @1:1-1:1 = add checked read %\(counter) @1:1-1:1, UInt 1 @1:1-1:1
              goto bb\(header)
            """
    }
    return """
        main "main()"
        func "main()"() -> Void {
        \(locals.joined(separator: "\n"))
        \(blocks.joined(separator: "\n"))
        bb\(3 * loops):
        \(retiringLoop(loops - 1))
          return
        }
        """
}

/// The retirements of the count and the test of loop `loop` as it ends, or none before the first loop.
private func retiringLoop(_ loop: Int) -> String {
    guard loop >= 0 else { return "" }
    return "  retire %\(3 * loop + 1)\n  retire %\(3 * loop)"
}

private let retiredUses = [
    RetiredUse(
        testDescription: "a use after a retirement in the same block",
        blocks: """
              retire %0
              begin a0 read %0 @1:1-1:2
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:2
              end a0
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
              begin a0 read %0 @1:1-1:2
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:2
              end a0
              return
            """,
        message: "the IR uses %0 at bb2, where it is retired",
    ),
    RetiredUse(
        testDescription: "a use that a loop's next pass reaches after the retirement",
        blocks: """
              goto bb1
            bb1:
              begin a0 read %0 @1:1-1:2
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:2
              end a0
              retire %0
              goto bb1
            """,
        message: "the IR uses %0 at bb1, where it is retired",
    ),
    RetiredUse(
        testDescription: "uses in two blocks, of which the earlier block's is named",
        blocks: """
              retire %0
              branch true, bb1, bb2
            bb1:
              begin a0 read %0 @1:1-1:2
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:2
              end a0
              return
            bb2:
              begin a1 read %0 @1:1-1:2
              _ = call builtin "print(_: &Int)"(a1) @1:1-1:2
              end a1
              return
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
