import RayoCheckedProgram
@testable import RayoIR
import Testing

/// IR that needs an access before its beginning, in the order of the blocks or on some path, and what the verifier of
/// the rules the emitter trusts says is wrong with it.
struct UnbegunAccess: CustomTestStringConvertible, Sendable {
    let testDescription: String
    /// The blocks of `main`, as text, after its assignment of the Int local `%0`.
    let blocks: String
    let message: String
}

@Suite("Verifying that each access begins before its uses")
struct AccessBeginningTests {
    @Test(arguments: accessesUsedInAnEarlierBlock)
    func `a use in a block before the one that begins the access is a violation, whatever the paths`(
        access: UnbegunAccess,
    ) throws {
        let program = try IRParser.program(from: borrowing(access.blocks))
        let violation = IRViolation(function: "main()", message: access.message)
        #expect(IRVerifier.verify(program, from: .ownership) == violation)
        #expect(IRVerifier.verifyEmitterRules(program) == violation)
    }

    @Test(arguments: accessesSomePathHasNotBegun)
    func `a use that a path reaches without beginning the access is a violation`(access: UnbegunAccess) throws {
        let program = try IRParser.program(from: borrowing(access.blocks))
        #expect(IRVerifier.verifyEmitterRules(program) == IRViolation(function: "main()", message: access.message))
    }

    @Test func `an access that a second statement begins is a violation`() throws {
        var program = try IRParser.program(from: borrowing("""
              branch true, bb1, bb2
            bb1:
              begin a0 read %0 @1:1-1:2
              end a0
              goto bb3
            bb2:
              goto bb3
            bb3:
              return
            """))
        // The IR's text can't begin an access twice, so the second beginning is written into the parsed body.
        let main = FunctionID(index: 0)
        var body = try #require(program.bodies[main])
        body.blocks[2].statements = body.blocks[1].statements
        program.bodies[main] = body

        let violation = IRViolation(
            function: "main()", message: "the IR begins a0 at bb2, after another statement that begins it",
        )
        #expect(IRVerifier.verify(program, from: .ownership) == violation)
        #expect(IRVerifier.verifyEmitterRules(program) == violation)
    }

    @Test func `an access that begins on each pass of a loop, before its use, is no violation`() throws {
        let program = try IRParser.program(from: borrowing("""
              goto bb1
            bb1:
              begin a0 read %0 @1:1-1:2
              _ = call "f(_: &Int)"(a0) @1:1-1:2
              end a0
              branch true, bb1, bb2
            bb2:
              return
            """))
        #expect(IRVerifier.verify(program, from: .ownership) == nil)
        #expect(IRVerifier.verifyEmitterRules(program) == nil)
    }

    @Test func `a use after the access ends is no violation of the rules the emitter trusts`() throws {
        let program = try IRParser.program(from: borrowing("""
              begin a0 read %0 @1:1-1:2
              end a0
              _ = call "f(_: &Int)"(a0) @1:1-1:2
              return
            """))
        #expect(IRVerifier.verifyEmitterRules(program) == nil)
    }
}

/// Bodies that begin an access in a block after one that uses it. Every path to the use begins the access first,
/// except in the block that no path reaches.
private let accessesUsedInAnEarlierBlock = [
    UnbegunAccess(
        testDescription: "an access passed to a call in a block before the one that begins it",
        blocks: """
              goto bb2
            bb1:
              _ = call "f(_: &Int)"(a0) @1:1-1:2
              end a0
              return
            bb2:
              begin a0 read %0 @1:1-1:2
              goto bb1
            """,
        message: "the IR uses a0 at bb1, before its beginning in the order of the blocks",
    ),
    UnbegunAccess(
        testDescription: "a value made to depend on an access in a block before the one that begins it",
        blocks: """
              goto bb2
            bb1:
              depend %0 on a0
              end a0
              return
            bb2:
              begin a0 read %0 @1:1-1:2
              goto bb1
            """,
        message: "the IR uses a0 at bb1, before its beginning in the order of the blocks",
    ),
    UnbegunAccess(
        testDescription: "an access passed to a call in a block that no path reaches, before the one that begins it",
        blocks: """
              goto bb2
            bb1:
              _ = call "f(_: &Int)"(a0) @1:1-1:2
              return
            bb2:
              begin a0 read %0 @1:1-1:2
              end a0
              return
            """,
        message: "the IR uses a0 at bb1, before its beginning in the order of the blocks",
    ),
]

/// Bodies that begin an access in a block before the one that uses it, on one of the two paths to the use.
private let accessesSomePathHasNotBegun = [
    UnbegunAccess(
        testDescription: "an access passed to a call that one of two paths hasn't begun",
        blocks: """
              branch true, bb1, bb2
            bb1:
              begin a0 read %0 @1:1-1:2
              goto bb2
            bb2:
              _ = call "f(_: &Int)"(a0) @1:1-1:2
              return
            """,
        message: "the IR uses a0 at bb2, which a path reaches without beginning it",
    ),
    UnbegunAccess(
        testDescription: "a value made to depend on an access that one of two paths hasn't begun",
        blocks: """
              branch true, bb1, bb2
            bb1:
              begin a0 read %0 @1:1-1:2
              goto bb2
            bb2:
              depend %0 on a0
              return
            """,
        message: "the IR uses a0 at bb2, which a path reaches without beginning it",
    ),
]
