import RayoOwnership
import Testing
import RayoDiagnostics
import RayoIR
import RayoCheckedProgram
import RayoSource

struct InitializationCheckerTests {
    @Test func `a use of a local after a move reports that it was moved, at the use`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              %1 @1:1-1:1 = operand move %0 @2:1-2:1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedAfterMove(name: "x"), at: at(2), labeling: moves(at: [1])),
        ])
    }

    @Test func `a move uses the local as a read does, so moving it again is reported there`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              %1 @1:1-1:1 = operand move %0 @2:1-2:1 @1:1-1:1
              %1 @1:1-1:1 = operand move %0 @2:2-2:2 @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedAfterMove(name: "x"), at: at(2), labeling: moves(at: [1])),
        ])
    }

    @Test
    func `a move takes a value only where the local holds one, so a move that is an error takes nothing`() throws {
        let blocks = """
            bb0:
              declare %2
              %2 @2:2-2:2 = operand move %2 @2:1-2:1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %2 @2:3-2:3) @1:1-1:1
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              %1 @1:1-1:1 = operand move %0 @2:4-2:4 @1:1-1:1
              %1 @1:1-1:1 = operand move %0 @2:5-2:5 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:6-2:6) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedUninitialized(name: "k"), at: at(1)),
            Diagnostic(.usedAfterMove(name: "x"), at: at(5), labeling: moves(at: [4])),
        ])
    }

    @Test func `an assignment gives a moved local a value again`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              %1 @1:1-1:1 = operand move %0 @2:1-2:1 @1:1-1:1
              %0 @1:1-1:1 = operand 2 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              _ = call builtin "print(_: Int)"(read %1 @1:1-1:1) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test(arguments: ["Int", "owned Int", "mutable Int"])
    func `a parameter holds its argument from the function's entry, whatever its convention`(parameter: String) throws {
        let function = (name: "f(_: Int)", text: """
            func "f(_: Int)"(_: \(parameter)) -> Void {
              param %0 n: \(parameter) @1:1-1:1
            bb0:
              _ = call builtin "print(_: Int)"(read %0 @2:1-2:1) @1:1-1:1
              return
            }
            """)
        #expect(try checked(function).errors == [])
    }

    @Test(arguments: [
        (true, ErrorCode.usedAfterMaybeMove(name: "x"), [1]), (false, .usedAfterMove(name: "x"), [1, 2]),
    ])
    func `a local moved on some of the paths that join may have been moved, and one moved on all of them was moved`(
        keptOnOnePath: Bool, expected: ErrorCode, moveColumns: [Int],
    ) throws {
        let otherwise = keptOnOnePath ? "" : "%1 @1:1-1:1 = operand move %0 @2:2-2:2 @1:1-1:1"
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              branch true, bb1, bb2
            bb1:
              %1 @1:1-1:1 = operand move %0 @2:1-2:1 @1:1-1:1
              goto bb3
            bb2:
              \(otherwise)
              goto bb3
            bb3:
              _ = call builtin "print(_: Int)"(read %0 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(expected, at: at(3), labeling: moves(at: moveColumns)),
        ])
    }

    @Test(arguments: [
        (false, [Diagnostic(.usedAfterMaybeMove(name: "x"), at: at(1), labeling: moves(at: [1]))]), (true, []),
    ])
    func `a move in a loop's body leaves the local without a value on the next pass, unless the body assigns it again`(
        assignsAgain: Bool, expected: [Diagnostic],
    ) throws {
        let assignment = assignsAgain ? "%0 @1:1-1:1 = operand 2 @1:1-1:1" : ""
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb1
            bb1:
              branch true, bb2, bb3
            bb2:
              _ = operand move %0 @2:1-2:1 @1:1-1:1
              \(assignment)
              goto bb1
            bb3:
              return
            """
        #expect(try checked(function(blocks)).errors == expected)
    }

    @Test func `a branch's condition and a return's result are uses, and a return's result may be a move`() throws {
        let blocks = """
            bb0:
              %6 @1:1-1:1 = operand true @1:1-1:1
              _ = operand move %6 @2:1-2:1 @1:1-1:1
              branch read %6 @2:2-2:2, bb1, bb1
            bb1:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              %1 @1:1-1:1 = operand move %0 @2:3-2:3 @1:1-1:1
              return move %0 @2:4-2:4
            """
        #expect(try checked(function(blocks, result: "Int")).errors == [
            Diagnostic(.usedAfterMove(name: "b"), at: at(2), labeling: moves(at: [1])),
            Diagnostic(.usedAfterMove(name: "x"), at: at(4), labeling: moves(at: [3])),
        ])
    }

    @Test func `a block that no path reaches reports nothing`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              return move %0 @2:1-2:1
            bb1:
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              return 0
            """
        #expect(try checked(function(blocks, result: "Int")).errors == [])
    }

    @Test func `the uses that the same moves reach are reported once, at the first of them in the source`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              %1 @1:1-1:1 = operand move %0 @2:1-2:1 @1:1-1:1
              %1 @1:1-1:1 = add checked read %0 @2:3-2:3, read %0 @2:2-2:2 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:4-2:4) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedAfterMove(name: "x"), at: at(2), labeling: moves(at: [1])),
        ])
    }

    @Test func `a use that other moves reach is reported again`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              branch true, bb1, bb2
            bb1:
              %1 @1:1-1:1 = operand move %0 @2:1-2:1 @1:1-1:1
              goto bb3
            bb2:
              goto bb3
            bb3:
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              %0 @1:1-1:1 = operand 2 @1:1-1:1
              %1 @1:1-1:1 = operand move %0 @2:3-2:3 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:4-2:4) @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:5-2:5) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedAfterMaybeMove(name: "x"), at: at(2), labeling: moves(at: [1])),
            Diagnostic(.usedAfterMove(name: "x"), at: at(4), labeling: moves(at: [3])),
        ])
    }

    @Test
    func `a use of a local that nothing has assigned since its declaration reports that it isn't initialized`() throws {
        let blocks = """
            bb0:
              declare %0
              _ = call builtin "print(_: Int)"(read %0 @2:1-2:1) @1:1-1:1
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [Diagnostic(.usedUninitialized(name: "x"), at: at(1))])
    }

    @Test(arguments: [(true, [Diagnostic(.usedMaybeUninitialized(name: "x"), at: at(3))]), (false, [])])
    func `a local assigned on some of the paths that join isn't initialized on every path, unlike one assigned on all`(
        unassignedOnOnePath: Bool, expected: [Diagnostic],
    ) throws {
        let otherwise = unassignedOnOnePath ? "" : "%0 @1:1-1:1 = operand 2 @1:1-1:1"
        let blocks = """
            bb0:
              declare %0
              branch true, bb1, bb2
            bb1:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb3
            bb2:
              \(otherwise)
              goto bb3
            bb3:
              _ = call builtin "print(_: Int)"(read %0 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == expected)
    }

    @Test func `a local moved on one path and never assigned on the other may have been moved`() throws {
        let blocks = """
            bb0:
              declare %0
              branch true, bb1, bb2
            bb1:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              %1 @1:1-1:1 = operand move %0 @2:1-2:1 @1:1-1:1
              goto bb2
            bb2:
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedAfterMaybeMove(name: "x"), at: at(2), labeling: moves(at: [1])),
        ])
    }

    @Test
    func `a declaration in a loop's body leaves the local without a value, whatever the last pass assigned`() throws {
        let blocks = """
            bb0:
              goto bb1
            bb1:
              branch true, bb2, bb3
            bb2:
              declare %2
              %2 @2:1-2:1 = operand 1 @1:1-1:1
              declare %0
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb1
            bb3:
              return
            """
        #expect(try checked(function(blocks)).errors == [Diagnostic(.usedUninitialized(name: "x"), at: at(2))])
    }

    @Test func `a 'var' may be assigned any number of times, and a 'let' only once on each path`() throws {
        let blocks = """
            bb0:
              declare %0
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              %0 @1:1-1:1 = operand 2 @1:1-1:1
              declare %2
              %2 @2:1-2:1 = operand 1 @1:1-1:1
              %2 @2:2-2:2 = operand 2 @1:1-1:1
              %2 @2:3-2:3 = operand 3 @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.letAssignedTwice(name: "k"), at: at(2)), Diagnostic(.letAssignedTwice(name: "k"), at: at(3)),
        ])
    }

    @Test func `a 'let' that a move left without a value was still assigned, so it can't be assigned again`() throws {
        let blocks = """
            bb0:
              declare %2
              %2 @1:1-1:1 = operand 1 @1:1-1:1
              %1 @1:1-1:1 = operand move %2 @2:1-2:1 @1:1-1:1
              %2 @2:2-2:2 = operand 2 @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [Diagnostic(.letAssignedTwice(name: "k"), at: at(2))])
    }

    @Test(arguments: [true, false])
    func `a 'let' assigned on some of the paths that join, or on an earlier pass of a loop, may have been assigned`(
        inLoop: Bool,
    ) throws {
        let blocks = inLoop ? """
            bb0:
              declare %2
              goto bb1
            bb1:
              branch true, bb2, bb3
            bb2:
              %2 @2:1-2:1 = operand 1 @1:1-1:1
              goto bb1
            bb3:
              return
            """ : """
            bb0:
              declare %2
              branch true, bb1, bb2
            bb1:
              %2 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb2
            bb2:
              %2 @2:1-2:1 = operand 2 @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [Diagnostic(.letMaybeAssignedTwice(name: "k"), at: at(1))])
    }

    @Test func `the uses that no assignment reaches since a declaration are reported once for each local`() throws {
        let blocks = """
            bb0:
              declare %0
              declare %1
              _ = call builtin "print(_: Int)"(read %0 @2:1-2:1) @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              _ = call builtin "print(_: Int)"(read %1 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedUninitialized(name: "x"), at: at(1)), Diagnostic(.usedUninitialized(name: "y"), at: at(3)),
        ])
    }

    @Test(arguments: [
        ("declare %5", ErrorCode.usedUninitialized(name: "s"), []),
        (storeShot() + "\n  _ = operand move %5 @2:1-2:1 @1:1-1:1", .usedAfterMove(name: "s"), [1]),
    ])
    func `a store to a field uses its local, which must hold the rest of its value`(
        before: String, expected: ErrorCode, moveColumns: [Int],
    ) throws {
        let blocks = """
            bb0:
            \(before)
              %5.1.0 @2:2-2:2 = operand 9 @1:1-1:1
              _ = operand read %5 @2:3-2:3 @1:1-1:1
              return
            """
        // The read after the store has the same cause as the store, so the store alone is reported.
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(expected, at: at(2), labeling: moves(at: moveColumns)),
        ])
    }

    @Test func `a store to a field leaves its local holding its value, which a move may then take`() throws {
        let blocks = """
            bb0:
            \(storeShot())
              %5.0 @2:1-2:1 = operand 9 @1:1-1:1
              _ = operand move %5 @2:2-2:2 @1:1-1:1
              _ = operand read %5 @2:3-2:3 @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedAfterMove(name: "s"), at: at(3), labeling: moves(at: [2])),
        ])
    }

    @Test(arguments: [
        (
            "%1 @1:1-1:1 = operand move %0 @2:1-2:1 @1:1-1:1",
            "begin a0 read %0 @2:2-2:2\n  _ = call \"g(_: Int, _: Int)\"(a0, 1) @1:1-1:1",
            ErrorCode.usedAfterMove(name: "x"),
        ),
        (
            "_ = operand move %5.1.0 @2:1-2:1 @1:1-1:1",
            "begin a0 read %5.1 @2:2-2:2\n  _ = call \"take(_: Int, _: Hit)\"(1, a0) @1:1-1:1",
            .usedPartlyMoved(name: "s.hit", field: "s.hit.damage"),
        ),
    ])
    func `an access begun on a place uses it, as a read does`(
        move: String, access: String, expected: ErrorCode,
    ) throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
            \(storeShot())
              \(move)
              \(access)
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(expected, at: at(2), labeling: moves(at: [1])),
        ])
    }

    @Test func `the moves an error notes come in source order, whatever the order of their blocks`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              branch true, bb1, bb2
            bb1:
              _ = operand move %0 @2:2-2:2 @1:1-1:1
              goto bb3
            bb2:
              _ = operand move %0 @2:1-2:1 @1:1-1:1
              goto bb3
            bb3:
              _ = call builtin "print(_: Int)"(read %0 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedAfterMove(name: "x"), at: at(3), labeling: moves(at: [1, 2])),
        ])
    }

    @Test(arguments: [false, true])
    func `a path that returns doesn't reach the code after it, so a local only that path assigns holds no value there`(
        assignsBeforeReturning: Bool,
    ) throws {
        // As `if c { x = 1; return }` lowers, then a use of `x`. The rest of the branch after its `return`, `bb4`,
        // still goes on to the use, but no path reaches it.
        let assignment = assignsBeforeReturning ? "%0 @1:1-1:1 = operand 1 @1:1-1:1" : ""
        let blocks = """
            bb0:
              declare %0
              branch true, bb1, bb2
            bb1:
              \(assignment)
              return
            bb2:
              goto bb3
            bb3:
              _ = call builtin "print(_: Int)"(read %0 @2:1-2:1) @1:1-1:1
              return
            bb4:
              goto bb3
            """
        #expect(try checked(function(blocks)).errors == [Diagnostic(.usedUninitialized(name: "x"), at: at(1))])
    }

    @Test(arguments: [
        // As `if c { x = 1 } else { return }`, then a use of `x`.
        """
        bb0:
          declare %0
          branch true, bb1, bb2
        bb1:
          %0 @1:1-1:1 = operand 1 @1:1-1:1
          goto bb3
        bb2:
          return
        bb3:
          _ = call builtin "print(_: Int)"(read %0 @2:1-2:1) @1:1-1:1
          return
        """,
        // As `while true { if c { x = 1; break } }`, then a use of `x`.
        """
        bb0:
          declare %0
          goto bb1
        bb1:
          goto bb2
        bb2:
          branch true, bb3, bb4
        bb3:
          %0 @1:1-1:1 = operand 1 @1:1-1:1
          goto bb5
        bb4:
          goto bb1
        bb5:
          _ = call builtin "print(_: Int)"(read %0 @2:1-2:1) @1:1-1:1
          return
        """,
    ])
    func `a local that every path to a use assigns holds a value there, though another path returns or loops`(
        blocks: String,
    ) throws {
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test(arguments: [
        // A loop that assigns the local in its body.
        ("bb1:\n  branch true, bb2, bb3\nbb2:\n  %0 @1:1-1:1 = operand 1 @1:1-1:1\n  goto bb1", "bb3"),
        // A loop whose body may `continue` before it assigns the local.
        (
            """
            bb1:
              branch true, bb2, bb5
            bb2:
              branch true, bb3, bb4
            bb3:
              goto bb1
            bb4:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb1
            """,
            "bb5",
        ),
        // A `while true` whose body may `break` before it assigns the local, and does after.
        (
            """
            bb1:
              goto bb2
            bb2:
              branch true, bb3, bb4
            bb3:
              goto bb5
            bb4:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb5
            """,
            "bb5",
        ),
    ])
    func `a loop may leave without assigning a local its body assigns, so the local isn't initialized on every path`(
        loop: String, exit: String,
    ) throws {
        let blocks = """
            bb0:
              declare %0
              goto bb1
            \(loop)
            \(exit):
              _ = call builtin "print(_: Int)"(read %0 @2:1-2:1) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedMaybeUninitialized(name: "x"), at: at(1)),
        ])
    }

    @Test func `a 'let' assigned once on each of the paths that join was assigned once`() throws {
        let blocks = """
            bb0:
              declare %2
              branch true, bb1, bb2
            bb1:
              %2 @2:1-2:1 = operand 1 @1:1-1:1
              goto bb3
            bb2:
              %2 @2:2-2:2 = operand 2 @1:1-1:1
              goto bb3
            bb3:
              _ = call builtin "print(_: Int)"(read %2 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test(arguments: [
        ("goto bb2", ErrorCode.usedAfterMove(name: "x")), ("branch true, bb2, bb3", .usedAfterMaybeMove(name: "x")),
    ])
    func `a 'break' after a move leaves the loop without the local's value`(
        header: String, expected: ErrorCode,
    ) throws {
        // As `while true` or another loop lowers, whose body moves the local and breaks, so its end is on no path.
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb1
            bb1:
              \(header)
            bb2:
              _ = operand move %0 @2:1-2:1 @1:1-1:1
              goto bb3
            bb3:
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              return
            bb4:
              goto bb1
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(expected, at: at(2), labeling: moves(at: [1])),
        ])
    }

    @Test(arguments: [
        (true, [Diagnostic(.usedAfterMaybeMove(name: "x"), at: at(1), labeling: moves(at: [2]))]), (false, []),
    ])
    func `a 'continue' after a move goes back to the loop's header without the local's value`(
        continues: Bool, expected: [Diagnostic],
    ) throws {
        // The body reads the local, then may move it and `continue` past the assignment that gives it a value again.
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb1
            bb1:
              branch true, bb2, bb5
            bb2:
              _ = call builtin "print(_: Int)"(read %0 @2:1-2:1) @1:1-1:1
              branch true, bb3, bb4
            bb3:
              _ = operand move %0 @2:2-2:2 @1:1-1:1
              goto \(continues ? "bb1" : "bb4")
            bb4:
              %0 @1:1-1:1 = operand 5 @1:1-1:1
              goto bb1
            bb5:
              return
            """
        #expect(try checked(function(blocks)).errors == expected)
    }

    @Test func `the uses in a loop that the same moves reach are reported once, at the first of them in the source`()
        throws {
        // As `while x > 0 { let y = x }` lowers: the header's read and the body's move both come after the move the
        // last pass made.
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb1
            bb1:
              %6 @1:1-1:1 = greater read %0 @2:1-2:1, 0 @1:1-1:1
              branch read %6 @1:1-1:1, bb2, bb3
            bb2:
              %1 @1:1-1:1 = operand move %0 @2:2-2:2 @1:1-1:1
              goto bb1
            bb3:
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedAfterMaybeMove(name: "x"), at: at(1), labeling: moves(at: [2])),
        ])
    }
}

struct FieldMoveTests {
    @Test func `a field moved out of a local leaves its other fields readable, and itself unreadable`() throws {
        let blocks = """
            bb0:
            \(storeShot())
              %4 @1:1-1:1 = operand move %5.1 @2:1-2:1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %5.0 @2:2-2:2) @1:1-1:1
              _ = call builtin "print(_: Int)"(read %5.1.0 @2:3-2:3) @1:1-1:1
              _ = operand read %4 @2:4-2:4 @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedAfterMove(name: "s.hit"), at: at(3), labeling: moves(at: [1])),
        ])
    }

    @Test(arguments: [
        ("%5.1", "read %5 @2:2-2:2", ErrorCode.usedPartlyMoved(name: "s", field: "s.hit")),
        ("%5.1", "move %5 @2:2-2:2", .usedPartlyMoved(name: "s", field: "s.hit")),
        ("%5.1.0", "read %5.1 @2:2-2:2", .usedPartlyMoved(name: "s.hit", field: "s.hit.damage")),
        ("%5.1.0", "read %5 @2:2-2:2", .usedPartlyMoved(name: "s", field: "s.hit.damage")),
    ])
    func `a place that a field was moved out of can't be read or moved whole, and the error names the field`(
        moved: String, use: String, expected: ErrorCode,
    ) throws {
        let blocks = """
            bb0:
            \(storeShot())
              _ = operand move \(moved) @2:1-2:1 @1:1-1:1
              _ = operand \(use) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [Diagnostic(expected, at: at(2), labeling: moves(at: [1]))])
    }

    @Test(arguments: [
        (ErrorCode.usedPartlyMoved(name: "s", field: "s.hit"),
         "'s.hit' was moved out of 's', so 's' can't be used as a whole"),
        (.usedMaybePartlyMoved(name: "s", field: "s.hit"),
         "'s.hit' may have been moved out of 's', so 's' can't be used as a whole"),
    ])
    func `the error at a use of a place a field was moved out of names the field and the place`(
        code: ErrorCode, message: String,
    ) {
        #expect(code.message == message)
    }

    @Test(arguments: [("%5.1", "%5.1"), ("%5.1.0", "%5.1.0"), ("%5.1.0", "%5.1")])
    func `assigning a moved field, or a field that holds it, makes the local whole again`(
        moved: String, assigned: String,
    ) throws {
        // A `Hit` replaces a moved `hit`, and an Int its `damage`.
        let newValue = assigned == "%5.1" ? "call \"Hit(damage: Int)\"(3)" : "operand 3"
        let blocks = """
            bb0:
            \(storeShot())
              _ = operand move \(moved) @2:1-2:1 @1:1-1:1
              \(assigned) @2:2-2:2 = \(newValue) @1:1-1:1
              _ = operand move %5 @2:3-2:3 @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test func `a local that is declared and never used needs no value`() throws {
        let blocks = "bb0:\n  declare %0\n  declare %6\n  return"
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test(arguments: [
        ("declare %7", Diagnostic(.usedUninitialized(name: "a"), at: at(2))),
        (
            "_ = operand move %7 @2:1-2:1 @1:1-1:1",
            Diagnostic(.usedAfterMove(name: "a"), at: at(2), labeling: moves(at: [1])),
        ),
    ])
    func `a store to an element uses its array, which must hold a value`(
        emptying: String, expected: Diagnostic,
    ) throws {
        // The array is filled, then left without a value before one of its elements is assigned.
        let blocks = """
            bb0:
              %4 @1:1-1:1 = call "Hit(damage: Int)"(7) @1:1-1:1
              %7 @1:1-1:1 = fill 2 of read %4 @1:1-1:1 @1:1-1:1
              \(emptying)
              %7[0] @2:2-2:2 = call "Hit(damage: Int)"(9) @1:1-1:1
              _ = call builtin "print(_: Int)"(read %7[0].0 @2:3-2:3) @1:1-1:1
              return
            """
        // The read after the store has the same cause, so the store alone is reported.
        #expect(try checked(function(blocks)).errors == [expected])
    }

    @Test func `a compound assignment to an element uses its array, which must hold a value`() throws {
        // As `a[0].damage += 1` lowers, where nothing has assigned `a`.
        let blocks = """
            bb0:
              declare %7
              %7[0].0 @2:1-2:1 = add checked read %7[0].0 @2:1-2:1, 1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %7[0].0 @2:2-2:2) @1:1-1:1
              return
            """
        // The use, the store and the read after them have the same cause, so the use alone is reported.
        #expect(try checked(function(blocks)).errors == [Diagnostic(.usedUninitialized(name: "a"), at: at(1))])
    }

    @Test(arguments: [
        ("%5", "%5.1.0", ErrorCode.usedAfterMove(name: "s")),
        ("%7", "%7[0].0", .usedAfterMove(name: "a")),
    ])
    func `a read of a part of a moved local, a field or an element, reports that the local was moved`(
        local: String, part: String, expected: ErrorCode,
    ) throws {
        let blocks = """
            bb0:
              %4 @1:1-1:1 = call "Hit(damage: Int)"(7) @1:1-1:1
              %7 @1:1-1:1 = fill 2 of read %4 @1:1-1:1 @1:1-1:1
            \(storeShot())
              _ = operand move \(local) @2:1-2:1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read \(part) @2:2-2:2) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(expected, at: at(2), labeling: moves(at: [1])),
        ])
    }

    @Test(arguments: [
        (false, [Diagnostic(.usedAfterMaybeMove(name: "s.hit"), at: at(1), labeling: moves(at: [1]))]), (true, []),
    ])
    func `a field moved in a loop's body may have been moved on the next pass, unless the body assigns it again`(
        assignsAgain: Bool, expected: [Diagnostic],
    ) throws {
        let assignment = assignsAgain ? "%5.1 @1:1-1:1 = operand move %4 @1:1-1:1 @1:1-1:1" : ""
        let blocks = """
            bb0:
            \(storeShot())
              goto bb1
            bb1:
              branch true, bb2, bb3
            bb2:
              %4 @1:1-1:1 = operand move %5.1 @2:1-2:1 @1:1-1:1
              \(assignment)
              goto bb1
            bb3:
              return
            """
        #expect(try checked(function(blocks)).errors == expected)
    }

    @Test func `a compound assignment's use comes before its store, so the errors about both come in that order`()
        throws {
        // As `k += 1` lowers where `k`, a `let`, was assigned on one path only.
        let blocks = """
            bb0:
              declare %2
              branch true, bb1, bb2
            bb1:
              %2 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb2
            bb2:
              %2 @2:1-2:1 = add checked read %2 @2:1-2:1, 1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %2 @1:1-1:1) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedMaybeUninitialized(name: "k"), at: at(1)),
            Diagnostic(.letMaybeAssignedTwice(name: "k"), at: at(1)),
        ])
    }

    @Test func `a field is assigned only where the field that holds it holds a value`() throws {
        let blocks = """
            bb0:
            \(storeShot())
              _ = operand move %5.1 @2:1-2:1 @1:1-1:1
              %5.1.0 @2:2-2:2 = operand 3 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %5.1.0 @2:3-2:3) @1:1-1:1
              return
            """
        // The read has the same cause as the store, so the store alone is reported.
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedAfterMove(name: "s.hit"), at: at(2), labeling: moves(at: [1])),
        ])
    }

    @Test func `assigning the whole local after a field was moved out of it makes it whole again`() throws {
        let blocks = """
            bb0:
            \(storeShot())
              _ = operand move %5.1 @2:1-2:1 @1:1-1:1
            \(storeShot(at: 2))
              _ = call builtin "print(_: Int)"(read %5.1.0 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test(arguments: [
        ("read %5 @2:2-2:2", ErrorCode.usedMaybePartlyMoved(name: "s", field: "s.hit")),
        ("read %5.1.0 @2:2-2:2", .usedAfterMaybeMove(name: "s.hit")),
        ("read %5.0 @2:2-2:2", nil),
    ])
    func `a field moved on some of the paths that join may have been moved, and so its local may be partly moved`(
        use: String, expected: ErrorCode?,
    ) throws {
        let blocks = """
            bb0:
            \(storeShot())
              branch true, bb1, bb2
            bb1:
              _ = operand move %5.1 @2:1-2:1 @1:1-1:1
              goto bb2
            bb2:
              _ = operand \(use) @1:1-1:1
              return
            """
        let expectedErrors = expected.map { [Diagnostic($0, at: at(2), labeling: moves(at: [1]))] }
        #expect(try checked(function(blocks)).errors == expectedErrors ?? [])
    }

    @Test func `a field moved on every path that joins was moved`() throws {
        let blocks = """
            bb0:
            \(storeShot())
              branch true, bb1, bb2
            bb1:
              _ = operand move %5.1 @2:1-2:1 @1:1-1:1
              goto bb3
            bb2:
              _ = operand move %5.1 @2:2-2:2 @1:1-1:1
              goto bb3
            bb3:
              _ = call builtin "print(_: Int)"(read %5.1.0 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(.usedAfterMove(name: "s.hit"), at: at(3), labeling: moves(at: [1, 2])),
        ])
    }
}

/// The moves at `columns`, each labeled as a move, as an error notes the moves that caused it.
private func moves(at columns: [Int]) -> [Diagnostic.LabeledRange] {
    columns.map { Diagnostic.LabeledRange(.moved, at: at($0)) }
}
