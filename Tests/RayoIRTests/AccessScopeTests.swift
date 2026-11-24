import RayoCheckedProgram
@testable import RayoIR
import Testing

/// IR whose accesses don't end once on every path from where each begins, and what the verifier says is wrong with it
/// once the ownership stage has written their ends.
struct UnscopedAccess: CustomTestStringConvertible, Sendable {
    let testDescription: String
    /// The blocks of `main`, as text, after its assignment of the Int local `%0`.
    let blocks: String
    let message: String
}

@Suite("Verifying where each access ends")
struct AccessScopeTests {
    @Test(arguments: unscopedAccesses)
    func `is a violation that names the access and the block`(access: UnscopedAccess) throws {
        let program = try IRParser.program(from: borrowing(access.blocks))
        let violation = IRViolation(function: "main()", message: access.message)
        #expect(IRVerifier.verify(program, from: .ownership) == violation)
    }

    @Test func `an access that ends once on every path from its beginning is no violation`() throws {
        let program = try IRParser.program(from: borrowing("""
              begin a0 read %0 @1:1-1:2
              _ = call "f(_: &Int)"(a0) @1:1-1:2
              branch true, bb1, bb2
            bb1:
              end a0
              goto bb3
            bb2:
              end a0
              goto bb3
            bb3:
              return
            """))
        #expect(IRVerifier.verify(program, from: .ownership) == nil)
    }

    @Test func `an access begun again while it is held is a violation`() throws {
        var program = try IRParser.program(from: borrowing("""
              begin a0 read %0 @1:1-1:2
              end a0
              return
            """))
        // The IR's text can't begin an access twice, so the second beginning is written into the parsed body.
        let main = FunctionID(index: 0)
        var body = try #require(program.bodies[main])
        body.blocks[0].statements.insert(body.blocks[0].statements[1], at: 2)
        program.bodies[main] = body

        let message = "the IR begins a0 at bb0, where it is already held"
        #expect(IRVerifier.verify(program, from: .ownership) == IRViolation(function: "main()", message: message))
    }

    @Test func `an access still held where a block ends in 'unreachable' is a violation`() throws {
        let program = try IRParser.program(from: borrowing("""
              begin a0 read %0 @1:1-1:2
              unreachable
            """))
        let body = try #require(program.bodies[FunctionID(index: 0)])

        // The whole verifier reports a reached `unreachable` first, so the check of the accesses runs alone.
        let violation = #expect(throws: IRViolation.self) {
            try AccessScopeVerifier(body: body, of: "main()").verify()
        }
        #expect(violation?.message == "the IR leaves the function at bb0 without ending a0")
    }

    @Test func `lowering's IR, whose ends the ownership stage writes later, ends no access`() throws {
        let program = try IRParser.program(from: borrowing("""
              begin a0 read %0 @1:1-1:2
              _ = call "f(_: &Int)"(a0) @1:1-1:2
              return
            """))
        #expect(IRVerifier.verify(program, from: .lowering) == nil)
    }

    @Test func `a block that no path reaches is no violation, whatever its accesses`() throws {
        let program = try IRParser.program(from: borrowing("""
              return
            bb1:
              begin a0 read %0 @1:1-1:2
              return
            """))
        #expect(IRVerifier.verify(program, from: .ownership) == nil)
    }
}

private let unscopedAccesses = [
    UnscopedAccess(
        testDescription: "an access not ended before the function returns",
        blocks: """
              begin a0 read %0 @1:1-1:2
              _ = call "f(_: &Int)"(a0) @1:1-1:2
              return
            """,
        message: "the IR leaves the function at bb0 without ending a0",
    ),
    UnscopedAccess(
        testDescription: "an access ended on one path but not on the other",
        blocks: """
              begin a0 read %0 @1:1-1:2
              branch true, bb1, bb2
            bb1:
              end a0
              return
            bb2:
              return
            """,
        message: "the IR leaves the function at bb2 without ending a0",
    ),
    UnscopedAccess(
        testDescription: "an access ended twice on a path",
        blocks: """
              begin a0 read %0 @1:1-1:2
              end a0
              end a0
              return
            """,
        message: "the IR ends a0 at bb0, where it isn't held",
    ),
    UnscopedAccess(
        testDescription: "an access ended on a path that never began it",
        blocks: """
              branch true, bb1, bb2
            bb1:
              begin a0 read %0 @1:1-1:2
              end a0
              return
            bb2:
              end a0
              return
            """,
        message: "the IR ends a0 at bb2, where it isn't held",
    ),
    UnscopedAccess(
        testDescription: "an access passed to a call after its end",
        blocks: """
              begin a0 read %0 @1:1-1:2
              end a0
              _ = call "f(_: &Int)"(a0) @1:1-1:2
              return
            """,
        message: "the IR uses a0 at bb0, where it isn't held",
    ),
    UnscopedAccess(
        testDescription: "a value made to depend on an access after its end",
        blocks: """
              begin a0 read %0 @1:1-1:2
              end a0
              depend %0 on a0
              return
            """,
        message: "the IR uses a0 at bb0, where it isn't held",
    ),
    UnscopedAccess(
        testDescription: "a block entered holding an access on one path and not on another",
        blocks: """
              begin a0 read %0 @1:1-1:2
              branch true, bb1, bb2
            bb1:
              end a0
              goto bb3
            bb2:
              goto bb3
            bb3:
              return
            """,
        message: "the IR enters bb3 holding a0 on one path and not on another",
    ),
    UnscopedAccess(
        testDescription: "a loop that begins an access on each pass and never ends it",
        blocks: """
              goto bb1
            bb1:
              begin a0 read %0 @1:1-1:2
              goto bb1
            """,
        message: "the IR enters bb1 holding a0 on one path and not on another",
    ),
]
