import RayoIR
import Testing

/// IR that steps into an element at an index a local holds, where nothing checks that index against the array's
/// count, and what the verifier says is wrong with it.
struct UncheckedIndex: CustomTestStringConvertible, Sendable {
    let testDescription: String
    /// The local `%1` that holds the index, as text.
    let local: String
    /// What `main` runs before it reads `%0[%1]`, the element of its array of two Ints at that index.
    let store: String
    let message: String
}

@Suite("Verifying that each index a local holds is checked against its array's count")
struct ElementIndexTests {
    @Test(arguments: uncheckedIndices)
    func `is a violation that names the local and the count`(index: UncheckedIndex) throws {
        let program = try IRParser.program(from: indexing(index.local, after: index.store))
        let violation = IRViolation(function: "main()", message: index.message)
        #expect(IRVerifier.verify(program, from: .lowering) == violation)
    }

    @Test func `a temporary index stored only by a check below its array's count is no violation`() throws {
        let program = try IRParser.program(from: indexing("temp %1: UInt", after: """
            %1 @1:1-1:2 = index UInt 1 below 2 @1:1-1:2
            """))
        #expect(IRVerifier.verify(program, from: .lowering) == nil)
    }

    @Test func `an index into an inner array is checked against the inner array's count`() throws {
        let program = try IRParser.program(from: """
            main "main()"
            func "main()"() -> Void {
              temp %0: [2 of [3 of Int]]
              temp %1: UInt
              temp %2: [3 of Int]
            bb0:
              %2 @1:1-1:2 = fill 3 of 0 @1:1-1:2
              %0 @1:1-1:2 = fill 2 of read %2 @1:1-1:2 @1:1-1:2
              %1 @1:1-1:2 = index UInt 1 below 2 @1:1-1:2
              _ = operand read %0[0][%1] @1:1-1:2 @1:1-1:2
              return
            }
            """)
        let message = "the IR indexes an array of 3 elements at %1, which it changes without checking it is below 3"
        #expect(IRVerifier.verify(program, from: .lowering) == IRViolation(function: "main()", message: message))
    }
}

/// A program whose `main` holds an array of two Ints in `%0` and the index `local` in `%1`, runs `store`, and then
/// reads the element of `%0` at `%1`. It declares `change(_: UInt)`, which takes a mutable UInt.
private func indexing(_ local: String, after store: String) -> String {
    """
    main "main()"
    func "main()"() -> Void {
      temp %0: [2 of Int]
      \(local)
    bb0:
      %0 @1:1-1:2 = fill 2 of 0 @1:1-1:2
      \(store)
      _ = operand read %0[%1] @1:1-1:2 @1:1-1:2
      return
    }
    func "change(_: UInt)"(_: mutable UInt) -> Void
    """
}

private let uncheckedIndices = [
    UncheckedIndex(
        testDescription: "an index that no statement stores",
        local: "temp %1: UInt",
        store: "",
        message: "the IR indexes an array of 2 elements at %1, which no statement stores",
    ),
    UncheckedIndex(
        testDescription: "an index that a local the source declares holds",
        local: "var %1 i: UInt @1:1-1:2",
        store: "%1 @1:1-1:2 = index UInt 1 below 2 @1:1-1:2",
        message: "the IR indexes an array of 2 elements at %1, which isn't a temporary",
    ),
    UncheckedIndex(
        testDescription: "an index stored without a check",
        local: "temp %1: UInt",
        store: "%1 @1:1-1:2 = operand UInt 1 @1:1-1:2",
        message: "the IR indexes an array of 2 elements at %1, which it changes without checking it is below 2",
    ),
    UncheckedIndex(
        testDescription: "an index checked against another count than its array's",
        local: "temp %1: UInt",
        store: "%1 @1:1-1:2 = index UInt 1 below 3 @1:1-1:2",
        message: "the IR indexes an array of 2 elements at %1, which it changes without checking it is below 2",
    ),
    UncheckedIndex(
        testDescription: "an index that a call may change through a modify access",
        local: "temp %1: UInt",
        store: """
            %1 @1:1-1:2 = index UInt 1 below 2 @1:1-1:2
              begin a0 modify %1 @1:1-1:2
              _ = call "change(_: UInt)"(a0) @1:1-1:2
            """,
        message: "the IR indexes an array of 2 elements at %1, which it changes without checking it is below 2",
    ),
]
