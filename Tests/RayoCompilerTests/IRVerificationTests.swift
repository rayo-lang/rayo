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
/// two Ints in `%1` and a UInt in `%2`, and it declares `f(_: Int)`, which borrows its one Int.
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
        func "f(_: Int)"(_: &Int) -> Void
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
    func `in a release build, IR the emitter receives that breaks its types, blocks or indices stops the compile`(
        broken: BrokenIR,
    ) throws {
        let program = try program(running: broken.blocks)
        #expect(throws: CompilationError.failed("internal error: in 'main()': \(broken.message)")) {
            try Compiler.verified(program, from: broken.stage, in: .release)
        }
    }

    @Test(arguments: brokenWhereOnlyADebugBuildChecks)
    func `in a release build, lowering's IR, and where accesses end and locals retire, go on unchecked`(
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

    @Test func `a release build checks a function eight times as long in well under sixty-four times as long`() throws {
        let short = try ownedIR(of: mainOfRounds(50))
        let long = try ownedIR(of: mainOfRounds(400))

        // A check that grows in line with the length takes about eight times as long. One that grows with its square
        // takes up to sixty-four times. Sixteen is a factor of two from the first, and of four from the second.
        let times = try fastestTimesToCheck(short, long, in: .release, runs: 3)
        #expect(times.long < times.short * 16)
    }
}

/// The IR that the ownership stage gives for `source`, which must check with no error. The stages run without the
/// pipeline, whose checks of their IR in a debug build would take far longer than the IR takes to make.
private func ownedIR(of source: String) throws -> IRProgram {
    var errors: [Diagnostic] = []
    let readSource = { (_: String) in Array(source.utf8) }
    let checked = try #require(try Compiler.checkedProgram("main.rayo", readFile: readSource, errors: &errors))
    let (owned, ownershipErrors) = OwnershipChecker.check(Lowering.lower(checked.program))
    try #require(errors.allSatisfy { $0.severity != .error } && ownershipErrors.isEmpty)
    return owned
}

/// The fastest time `build` of `rayoc` takes to check `short` and `long`, as the ownership stage's IR, of `runs`
/// runs each. The runs take the two in turn, so that a runner busy with other work during one run slows neither one's
/// time.
private func fastestTimesToCheck(
    _ short: IRProgram, _ long: IRProgram, in build: CompilerBuild, runs: Int,
) throws -> (short: Duration, long: Duration) {
    var shortTime = Duration.seconds(Int64.max)
    var longTime = Duration.seconds(Int64.max)
    for _ in 0..<runs {
        shortTime = min(shortTime, try timeToCheck(short, in: build))
        longTime = min(longTime, try timeToCheck(long, in: build))
    }
    return (shortTime, longTime)
}

/// How long `build` of `rayoc` takes to check `program`, as the ownership stage's IR. It throws where the checks
/// find a violation, since a check that stops at one measures only part of the work.
private func timeToCheck(_ program: IRProgram, in build: CompilerBuild) throws -> Duration {
    let clock = ContinuousClock()
    let start = clock.now
    _ = try Compiler.verified(program, from: .ownership, in: build)
    return clock.now - start
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
]

/// IR broken in a way only a debug build of `rayoc` checks: lowering's IR, whatever rule it breaks, and the ownership
/// stage's IR where its accesses end and its locals retire.
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
              _ = call "f(_: Int)"(a0) @1:1-1:2
              return
            """,
        message: "the IR leaves the function at bb0 without ending a0",
    ),
    BrokenIR(
        testDescription: "the ownership stage's IR that uses a retired local",
        stage: .ownership,
        blocks: """
              declare %0
              %0 @1:1-1:2 = operand 1 @1:1-1:2
              retire %0
              begin a0 read %0 @1:1-1:2
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:2
              end a0
              return
            """,
        message: "the IR uses %0 at bb0, where it is retired",
    ),
]
