@testable import RayoCompiler
import RayoDiagnostics
import RayoIR
import RayoOwnership
import Testing

/// IR that breaks one of the IR's rules, the stage that gave it, and what the verifier says is wrong with it.
struct BrokenIR: CustomTestStringConvertible, Sendable {
    let testDescription: String
    let stage: IRStage
    /// The blocks of `main`, which takes and returns nothing, as text.
    let blocks: String
    let message: String
}

/// A program whose `main`, which takes and returns nothing, runs `blocks`. Its `main` holds an Int in `%0`, an array of
/// two Ints in `%1` and a UInt in `%2`, and it declares `f(_: &Int)`, which borrows its one Int.
private func program(running blocks: String) throws -> IRProgram {
    try IRParser.program(from: """
        main "main()"
        func "main()"() -> Void {
          temp %0: Int
          temp %1: [2 of Int]
          temp %2: UInt
        bb0:
        \(blocks)
        }
        func "f(_: &Int)"(_: &Int) -> Void
        """)
}

@Suite("Verifying the IR a stage gives")
struct IRVerificationTests {
    @Test(arguments: brokenInTheIREveryBuildChecks + brokenWhereOnlyADebugBuildChecks)
    func `in a debug build, IR from either stage that breaks any rule stops the compile with an internal error`(
        broken: BrokenIR,
    ) throws {
        let program = try program(running: broken.blocks)
        #expect(throws: CompilationError.failed("internal error: in 'main()': \(broken.message)")) {
            try Compiler.verified(program, from: broken.stage, in: .debug)
        }
    }

    @Test(arguments: brokenInTheIREveryBuildChecks)
    func `in a release build, the emitter's IR that breaks its types, blocks, indices or local lives stops the compile`(
        broken: BrokenIR,
    ) throws {
        let program = try program(running: broken.blocks)
        #expect(throws: CompilationError.failed("internal error: in 'main()': \(broken.message)")) {
            try Compiler.verified(program, from: broken.stage, in: .release)
        }
    }

    @Test(arguments: brokenWhereOnlyADebugBuildChecks)
    func `in a release build, lowering's IR, and where accesses end, go on unchecked`(
        broken: BrokenIR,
    ) throws {
        let program = try program(running: broken.blocks)
        #expect(try Compiler.verified(program, from: broken.stage, in: .release) == program)
    }

    @Test(arguments: [IRStage.lowering, .ownership], [CompilerBuild.debug, .release])
    func `IR that keeps its rules goes on as it is`(stage: IRStage, build: CompilerBuild) throws {
        let program = try program(running: "  return")
        #expect(try Compiler.verified(program, from: stage, in: build) == program)
    }

    @Test(arguments: [CompilerBuild.debug, .release])
    func `the IR the ownership stage gives for rounds of checked indices keeps every rule either build checks`(
        build: CompilerBuild,
    ) throws {
        let owned = try ownedIR(of: mainOfRounds(4))
        #expect(try Compiler.verified(owned, from: .ownership, in: build) == owned)
    }
}

/// The IR that the ownership stage gives for `source`, which must check with no error.
private func ownedIR(of source: String) throws -> IRProgram {
    var errors: [Diagnostic] = []
    let readSource = { (_: String) in Array(source.utf8) }
    let checked = try #require(try Compiler.checkedProgram("main.rayo", readFile: readSource, errors: &errors))
    let (owned, ownershipErrors) = OwnershipChecker.check(Lowering.lower(checked.program))
    try #require(errors.allSatisfy { $0.severity != .error } && ownershipErrors.isEmpty)
    return owned
}

/// A `main` that takes `count` rounds over the array `a` of four Ints. Each round finds an element at an index a `let`
/// of its own holds, and keeps the element, plus the round's number, in `s` where that is larger, or else stores `s` in
/// the element.
private func mainOfRounds(_ count: Int) -> String {
    let rounds = (0..<count).map { round in
        """
            let i\(round): UInt = \(round % 4)
            let x\(round) = a[i\(round)] + \(round)
            if x\(round) > s { s = consume x\(round) } else { a[i\(round)] = copy s }
        """
    }
    return """
        func main() {
            var a: [4 of Int] = [1, 2, 3, 4]
            var s = 0
        \(rounds.joined(separator: "\n"))
            print(s)
            print(a[0])
        }
        """
}

/// The blocks of a `main` that finds an element of `%1` at the index `%2`, which it stores without checking it.
private let uncheckedIndex = """
      %1 @1:1-1:2 = fill 2 of 0 @1:1-1:2
      %2 @1:1-1:2 = operand UInt 1 @1:1-1:2
      _ = operand read %1[%2] @1:1-1:2 @1:1-1:2
    """
private let uncheckedIndexMessage =
    "the IR indexes an array of 2 elements at %2, which it changes without checking it is below 2"
private let typeMessage = "the IR returns a value of type Bool from a function that returns Void"

/// The blocks of a `main` that prints `%0` after it retires it.
private let retiredUse = """
      declare %0
      %0 @1:1-1:2 = operand 1 @1:1-1:2
      retire %0
      begin a0 read %0 @1:1-1:2
      _ = call builtin "print(_: &Int)"(a0) @1:1-1:2
      end a0
    """
private let retiredUseMessage = "the IR uses %0 at bb0, where it is retired"

/// IR the ownership stage gives, which the emitter receives, broken in a way every build of `rayoc` checks.
private let brokenInTheIREveryBuildChecks = [
    BrokenIR(
        testDescription: "the ownership stage's IR that breaks its types",
        stage: .ownership,
        blocks: "  return true",
        message: typeMessage,
    ),
    BrokenIR(
        testDescription: "the ownership stage's IR whose path reaches an 'unreachable'",
        stage: .ownership,
        blocks: "  goto bb1\nbb1:\n  unreachable",
        message: "the IR reaches bb1, which ends in unreachable",
    ),
    BrokenIR(
        testDescription: "the ownership stage's IR that finds an element at an unchecked index",
        stage: .ownership,
        blocks: uncheckedIndex + "\n  return",
        message: uncheckedIndexMessage,
    ),
    // The types are checked before the indices, since the index check takes each place's type as given.
    BrokenIR(
        testDescription: "the ownership stage's IR that breaks its types after an unchecked index",
        stage: .ownership,
        blocks: uncheckedIndex + "\n  return true",
        message: typeMessage,
    ),
    BrokenIR(
        testDescription: "the ownership stage's IR that uses a retired local",
        stage: .ownership,
        blocks: retiredUse + "\n  return",
        message: retiredUseMessage,
    ),
    // The rules every stage's IR keeps are checked before where locals retire, as a debug build checks them.
    BrokenIR(
        testDescription: "the ownership stage's IR that breaks its types after a use of a retired local",
        stage: .ownership,
        blocks: retiredUse + "\n  return true",
        message: typeMessage,
    ),
]

/// IR broken in a way only a debug build of `rayoc` checks: lowering's IR, whatever rule it breaks, and the ownership
/// stage's IR where its accesses end.
private let brokenWhereOnlyADebugBuildChecks = [
    BrokenIR(
        testDescription: "lowering's IR that breaks its types",
        stage: .lowering,
        blocks: "  return true",
        message: typeMessage,
    ),
    BrokenIR(
        testDescription: "lowering's IR that finds an element at an unchecked index",
        stage: .lowering,
        blocks: uncheckedIndex + "\n  return",
        message: uncheckedIndexMessage,
    ),
    BrokenIR(
        testDescription: "lowering's IR that retires a local",
        stage: .lowering,
        blocks: """
              declare %0
              %0 @1:1-1:2 = operand 1 @1:1-1:2
              retire %0
              return
            """,
        message: "the IR retires %0 at bb0, though only the ownership stage retires a local",
    ),
    BrokenIR(
        testDescription: "the ownership stage's IR that leaves an access unended",
        stage: .ownership,
        blocks: """
              %0 @1:1-1:2 = operand 1 @1:1-1:2
              begin a0 read %0 @1:1-1:2
              _ = call "f(_: &Int)"(a0) @1:1-1:2
              return
            """,
        message: "the IR leaves the function at bb0 without ending a0",
    ),
]
