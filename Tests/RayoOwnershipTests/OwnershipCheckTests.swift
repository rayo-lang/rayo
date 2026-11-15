import Testing
import RayoDiagnostics
import RayoIR
import RayoOwnership
import RayoSema

@Suite("Running the ownership checks over a program")
struct OwnershipCheckTests {
    @Test
    func `a use of a borrowed parameter after a move out of it isn't reported again as a use after a move`() throws {
        let blocks = """
            bb0:
              _ = operand move %0 @2:1-2:1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              return
            """
        #expect(try checked(takingInt(blocks)).errors == [Diagnostic(.moveFromParameter(name: "n"), at: at(1))])
    }

    @Test func `a 'let' assigned twice isn't reported again for the first value, which no code reads`() throws {
        let blocks = """
            bb0:
              declare %2
              %2 @2:1-2:1 = operand 1 @1:1-1:1
              %2 @2:2-2:2 = operand 2 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %2 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [Diagnostic(.letAssignedTwice(name: "k"), at: at(2))])
    }

    @Test func `a use of a local that holds no value isn't checked for conflicting accesses`() throws {
        // As `g(&x, x)` lowers, where nothing has assigned `x`.
        let blocks = """
            bb0:
              begin a0 modify static %0 @2:3-2:3
              begin a1 read static %0 @2:6-2:6
              _ = call "g(_: Int, _: Int)"(a0, a1) @1:1-1:1
              return
            """
        // Both accesses use `x` with the same cause, so only the first is reported.
        #expect(try checked(function(blocks)).errors == [Diagnostic(.usedUninitialized(name: "x"), at: at(3))])
    }

    @Test func `a function whose accesses conflict isn't checked for values no code reads`() throws {
        // As `g(&x, x)` lowers, then `y = 1`, which no code reads.
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 modify static %0 @2:3-2:3
              begin a1 read static %0 @2:6-2:6
              _ = call "g(_: Int, _: Int)"(a0, a1) @1:1-1:1
              %1 @2:9-2:9 = operand 1 @1:1-1:1
              return
            """
        let expected = Diagnostic(
            .usedWhileMutablyBorrowed(name: "x", borrowed: "x"), at: at(6), labeling: [.init(.borrowed, at: at(3))],
        )
        #expect(try checked(function(blocks)).errors == [expected])
    }

    @Test func `a function a check fails has no body, and one that passes has its accesses' ends written in`() throws {
        let failing = function("bb0:\n  %1 @2:5-2:5 = operand 1 @1:1-1:1\n  return", named: "failing()")
        let passing = function("""
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read static %0 @1:1-1:1
              _ = call "double(_: Int)"(a0) @1:1-1:1
              return
            """, named: "passing()")
        let ended = function("""
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read static %0 @1:1-1:1
              _ = call "double(_: Int)"(a0) @1:1-1:1
              end a0
              return
            """, named: "passing()")

        let (checked, errors) = OwnershipChecker.check(try program(of: [failing, passing] + callees))
        let expected = try program(of: [failing, ended] + callees)
        #expect(errors == [FunctionID(index: 0): [Diagnostic(.unreadValue(name: "y"), at: at(5))]])
        #expect(checked.bodies[FunctionID(index: 0)] == nil)
        #expect(checked.bodies[FunctionID(index: 1)] == expected.bodies[FunctionID(index: 1)])
    }

    @Test
    func `each function's errors come under its ID, in source order, and a function without any has none`() throws {
        // The first function's errors come after the second's in the source, and its own are out of order.
        let late = function("""
            bb0:
              %0 @2:7-2:7 = operand 1 @1:1-1:1
              %1 @2:6-2:6 = operand 1 @1:1-1:1
              return
            """, named: "late()")
        let early = function("bb0:\n  %0 @2:5-2:5 = operand 1 @1:1-1:1\n  return", named: "early()")
        let clean = function("bb0:\n  return", named: "clean()")

        let (_, reported) = OwnershipChecker.check(try program(of: [late, early, clean]))
        #expect(reported.mapValues { $0.map(\.range.start.column) } == [
            FunctionID(index: 0): [6, 7], FunctionID(index: 1): [5],
        ])
    }
}

/// The function `f(_: Int)`, made of `blocks`, whose one local is `n` (`%0`), a borrowed Int parameter.
private func takingInt(_ blocks: String) -> (name: String, text: String) {
    let text = """
        func "f(_: Int)"(Int) -> Void {
          param %0 n: Int
        \(blocks)
        }
        """
    return ("f(_: Int)", text)
}
