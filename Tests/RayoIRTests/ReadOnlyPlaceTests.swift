@testable import RayoIR
import Testing

/// IR that changes a place code may only read, and what the verifier says is wrong with it.
struct ReadOnlyChange: CustomTestStringConvertible, Sendable {
    let testDescription: String
    /// The statements of `f`, as text, before it returns.
    let statements: String
    let message: String
}

@Suite("Verifying that nothing changes a place code may only read")
struct ReadOnlyPlaceTests {
    @Test(arguments: readOnlyChanges, [IRStage.lowering, .ownership])
    func `a change of a place code may only read is a violation that names the local and what changes it`(
        change: ReadOnlyChange, stage: IRStage,
    ) throws {
        let program = try IRParser.program(from: changingPoints(change.statements))
        let violation = IRViolation(function: pointsFunction, message: change.message)
        #expect(IRVerifier.verify(program, from: stage) == violation)
    }

    @Test(arguments: readOnlyChanges)
    func `the rules the emitter takes as given refuse a change of a place code may only read`(
        change: ReadOnlyChange,
    ) throws {
        let program = try IRParser.program(from: changingPoints(change.statements))
        let violation = IRViolation(function: pointsFunction, message: change.message)
        #expect(IRVerifier.verifyEmitterRules(program) == violation)
    }

    @Test(arguments: allowedChanges)
    func `a change of a place code may change is no violation`(change: AllowedChange) throws {
        let program = try IRParser.program(from: changingPoints(change.statements))
        #expect(IRVerifier.verify(program, from: .lowering) == nil)
        #expect(IRVerifier.verifyEmitterRules(program) == nil)
    }
}

/// IR that changes a place code may change.
struct AllowedChange: CustomTestStringConvertible, Sendable {
    let testDescription: String
    /// The statements of `f`, as text, before it returns.
    let statements: String
}

/// The name of the function that `changingPoints` gives its statements to.
private let pointsFunction = "f(_: &Point, _: Point, _: mutable &Point)"

/// A program whose function `f` runs `statements` and returns. It takes a `Point` that it borrows in `%0`, one it
/// owns in `%1` and one it may change in `%2`, and holds one in the `let` `%3`, the `ref let` `%4`, the `var` `%5`
/// and the temporary `%6`. A `Point` holds two Ints.
private func changingPoints(_ statements: String) -> String {
    """
    struct Point {
      var x: Int
      var y: Int
    }
    main "main()"
    func "main()"() -> Void {
    bb0:
      return
    }
    func "\(pointsFunction)"(_: &Point, _: Point, _: mutable &Point) -> Void {
      param %0 borrowed: &Point @1:1-1:2
      param %1 owned: Point @1:1-1:2
      param %2 changed: mutable &Point @1:1-1:2
      let %3 fixed: Point @1:1-1:2
      ref %4 view: Point @1:1-1:2
      var %5 free: Point @1:1-1:2
      temp %6: Point
    bb0:
    \(statements)
      return
    }
    """
}

/// A statement that stores a `Point` in `place`, or an Int where `place` is a field of one.
private func store(to place: String) -> String {
    let value = place.contains(".") ? "1" : "read %1 @1:1-1:2"
    return "  \(place) @1:1-1:2 = operand \(value) @1:1-1:2"
}

/// A statement that begins a modify access to `place`.
private func modify(_ place: String) -> String {
    "  begin a0 modify \(place) @1:1-1:2"
}

private let borrowedParameter = "the parameter 'borrowed' of &Point, which may not change so"
private let fixedLet = "the let 'fixed', which may not change so"
private let viewReferenceLet = "the ref let 'view', which may not change so"

private let readOnlyChanges = [
    ReadOnlyChange(
        testDescription: "a store to a borrowed parameter",
        statements: store(to: "%0"),
        message: "the IR stores to %0, \(borrowedParameter)",
    ),
    ReadOnlyChange(
        testDescription: "a store to part of a borrowed parameter",
        statements: store(to: "%0.1"),
        message: "the IR stores to part of %0, \(borrowedParameter)",
    ),
    ReadOnlyChange(
        testDescription: "a modify access to a borrowed parameter",
        statements: modify("%0"),
        message: "the IR begins a modify access to %0, \(borrowedParameter)",
    ),
    ReadOnlyChange(
        testDescription: "a modify access to part of a borrowed parameter",
        statements: modify("%0.0"),
        message: "the IR begins a modify access to part of %0, \(borrowedParameter)",
    ),
    ReadOnlyChange(
        testDescription: "a store to part of a 'let'",
        statements: store(to: "%3.0"),
        message: "the IR stores to part of %3, \(fixedLet)",
    ),
    ReadOnlyChange(
        testDescription: "a modify access to a 'let'",
        statements: modify("%3"),
        message: "the IR begins a modify access to %3, \(fixedLet)",
    ),
    ReadOnlyChange(
        testDescription: "a modify access to part of a 'let'",
        statements: modify("%3.1"),
        message: "the IR begins a modify access to part of %3, \(fixedLet)",
    ),
    ReadOnlyChange(
        testDescription: "a store to part of a 'ref let'",
        statements: store(to: "%4.0"),
        message: "the IR stores to part of %4, \(viewReferenceLet)",
    ),
    ReadOnlyChange(
        testDescription: "a modify access to a 'ref let'",
        statements: modify("%4"),
        message: "the IR begins a modify access to %4, \(viewReferenceLet)",
    ),
    ReadOnlyChange(
        testDescription: "a modify access to part of a 'ref let'",
        statements: modify("%4.1"),
        message: "the IR begins a modify access to part of %4, \(viewReferenceLet)",
    ),
    // Every block is checked, whether or not a path reaches it.
    ReadOnlyChange(
        testDescription: "a store to a borrowed parameter in a block no path reaches",
        statements: "  return\nbb1:\n" + store(to: "%0"),
        message: "the IR stores to %0, \(borrowedParameter)",
    ),
]

private let allowedChanges = [
    AllowedChange(testDescription: "a store that gives a 'let' its value", statements: store(to: "%3")),
    AllowedChange(testDescription: "a store that gives a 'ref let' its value", statements: store(to: "%4")),
    AllowedChange(testDescription: "a store to a 'var'", statements: store(to: "%5")),
    AllowedChange(testDescription: "a store to part of a 'var'", statements: store(to: "%5.0")),
    AllowedChange(testDescription: "a modify access to a 'var'", statements: modify("%5")),
    AllowedChange(testDescription: "a modify access to part of a 'var'", statements: modify("%5.1")),
    AllowedChange(testDescription: "a store to an owned parameter", statements: store(to: "%1")),
    AllowedChange(testDescription: "a store to part of an owned parameter", statements: store(to: "%1.0")),
    AllowedChange(testDescription: "a modify access to an owned parameter", statements: modify("%1")),
    AllowedChange(testDescription: "a modify access to part of an owned parameter", statements: modify("%1.1")),
    AllowedChange(testDescription: "a store to a mutable parameter", statements: store(to: "%2")),
    AllowedChange(testDescription: "a store to part of a mutable parameter", statements: store(to: "%2.0")),
    AllowedChange(testDescription: "a modify access to a mutable parameter", statements: modify("%2")),
    AllowedChange(testDescription: "a modify access to part of a mutable parameter", statements: modify("%2.1")),
    AllowedChange(testDescription: "a store to a temporary", statements: store(to: "%6")),
    AllowedChange(testDescription: "a store to part of a temporary", statements: store(to: "%6.0")),
    AllowedChange(testDescription: "a modify access to a temporary", statements: modify("%6")),
]
