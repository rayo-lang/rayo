import Testing
import RayoDiagnostics
import RayoIR
import RayoOwnership
import RayoSema
import RayoSource

struct InitializationCheckerTests {
    @Test func `a use of a local after a move reports that it was moved, at the use`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = use 1 @1:1-1:1
              %1 @1:1-1:1 = use move %0 @2:1-2:1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(.usedAfterMove(name: "x"), at: at(2), labeling: moves(at: [1]))])
    }

    @Test func `a move uses the local as a read does, so moving it again is reported there`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = use 1 @1:1-1:1
              %1 @1:1-1:1 = use move %0 @2:1-2:1 @1:1-1:1
              %1 @1:1-1:1 = use move %0 @2:2-2:2 @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(.usedAfterMove(name: "x"), at: at(2), labeling: moves(at: [1]))])
    }

    @Test
    func `a move takes a value only where the local holds one, so a move that is an error takes nothing`() throws {
        let blocks = """
            bb0:
              declare %2
              %2 @2:2-2:2 = use move %2 @2:1-2:1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %2 @2:3-2:3) @1:1-1:1
              %0 @1:1-1:1 = use 1 @1:1-1:1
              %1 @1:1-1:1 = use move %0 @2:4-2:4 @1:1-1:1
              %1 @1:1-1:1 = use move %0 @2:5-2:5 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:6-2:6) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [
            Diagnostic(.usedUninitialized(name: "k"), at: at(1)),
            Diagnostic(.usedAfterMove(name: "x"), at: at(5), labeling: moves(at: [4])),
        ])
    }

    @Test func `an assignment gives a moved local a value again`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = use 1 @1:1-1:1
              %1 @1:1-1:1 = use move %0 @2:1-2:1 @1:1-1:1
              %0 @1:1-1:1 = use 2 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [])
    }

    @Test func `a parameter holds its argument from the function's entry`() throws {
        let blocks = """
            bb0:
              _ = call builtin "print(_: Int)"(read %0 @2:1-2:1) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks, parameters: "Int") == [])
    }

    @Test(arguments: [
        (true, ErrorCode.usedAfterMaybeMove(name: "x"), [1]), (false, .usedAfterMove(name: "x"), [1, 2]),
    ])
    func `a local moved on some of the paths that join may have been moved, and one moved on all of them was moved`(
        keptOnOnePath: Bool, expected: ErrorCode, moveColumns: [Int],
    ) throws {
        let otherwise = keptOnOnePath ? "" : "%1 @1:1-1:1 = use move %0 @2:2-2:2 @1:1-1:1"
        let blocks = """
            bb0:
              %0 @1:1-1:1 = use 1 @1:1-1:1
              branch true, bb1, bb2
            bb1:
              %1 @1:1-1:1 = use move %0 @2:1-2:1 @1:1-1:1
              goto bb3
            bb2:
              \(otherwise)
              goto bb3
            bb3:
              _ = call builtin "print(_: Int)"(read %0 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(expected, at: at(3), labeling: moves(at: moveColumns))])
    }

    @Test(arguments: [
        (false, [Diagnostic(.usedAfterMaybeMove(name: "x"), at: at(1), labeling: moves(at: [1]))]), (true, []),
    ])
    func `a move in a loop's body leaves the local without a value on the next pass, unless the body assigns it again`(
        assignsAgain: Bool, expected: [Diagnostic],
    ) throws {
        let assignment = assignsAgain ? "%0 @1:1-1:1 = use 2 @1:1-1:1" : ""
        let blocks = """
            bb0:
              %0 @1:1-1:1 = use 1 @1:1-1:1
              goto bb1
            bb1:
              branch true, bb2, bb3
            bb2:
              %1 @1:1-1:1 = use move %0 @2:1-2:1 @1:1-1:1
              \(assignment)
              goto bb1
            bb3:
              return
            """
        #expect(try errors(in: blocks) == expected)
    }

    @Test func `a branch's condition and a return's result are uses, and a return's result may be a move`() throws {
        let blocks = """
            bb0:
              %6 @1:1-1:1 = use true @1:1-1:1
              _ = use move %6 @2:1-2:1 @1:1-1:1
              branch read %6 @2:2-2:2, bb1, bb1
            bb1:
              %0 @1:1-1:1 = use 1 @1:1-1:1
              %1 @1:1-1:1 = use move %0 @2:3-2:3 @1:1-1:1
              return move %0 @2:4-2:4
            """
        #expect(try errors(in: blocks, result: "Int") == [
            Diagnostic(.usedAfterMove(name: "b"), at: at(2), labeling: moves(at: [1])),
            Diagnostic(.usedAfterMove(name: "x"), at: at(4), labeling: moves(at: [3])),
        ])
    }

    @Test func `a block that no path reaches reports nothing`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = use 1 @1:1-1:1
              return move %0 @2:1-2:1
            bb1:
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              return 0
            """
        #expect(try errors(in: blocks, result: "Int") == [])
    }

    @Test func `the uses that the same moves reach are reported once, at the first of them in the source`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = use 1 @1:1-1:1
              %1 @1:1-1:1 = use move %0 @2:1-2:1 @1:1-1:1
              %1 @1:1-1:1 = add checked read %0 @2:3-2:3, read %0 @2:2-2:2 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:4-2:4) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(.usedAfterMove(name: "x"), at: at(2), labeling: moves(at: [1]))])
    }

    @Test func `a use that other moves reach is reported again`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = use 1 @1:1-1:1
              branch true, bb1, bb2
            bb1:
              %1 @1:1-1:1 = use move %0 @2:1-2:1 @1:1-1:1
              goto bb3
            bb2:
              goto bb3
            bb3:
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              %0 @1:1-1:1 = use 2 @1:1-1:1
              %1 @1:1-1:1 = use move %0 @2:3-2:3 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:4-2:4) @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:5-2:5) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [
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
              %0 @1:1-1:1 = use 1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(.usedUninitialized(name: "x"), at: at(1))])
    }

    @Test(arguments: [(true, [Diagnostic(.usedMaybeUninitialized(name: "x"), at: at(3))]), (false, [])])
    func `a local assigned on some of the paths that join isn't initialized on every path, unlike one assigned on all`(
        unassignedOnOnePath: Bool, expected: [Diagnostic],
    ) throws {
        let otherwise = unassignedOnOnePath ? "" : "%0 @1:1-1:1 = use 2 @1:1-1:1"
        let blocks = """
            bb0:
              declare %0
              branch true, bb1, bb2
            bb1:
              %0 @1:1-1:1 = use 1 @1:1-1:1
              goto bb3
            bb2:
              \(otherwise)
              goto bb3
            bb3:
              _ = call builtin "print(_: Int)"(read %0 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == expected)
    }

    @Test func `a local moved on one path and never assigned on the other may have been moved`() throws {
        let blocks = """
            bb0:
              declare %0
              branch true, bb1, bb2
            bb1:
              %0 @1:1-1:1 = use 1 @1:1-1:1
              %1 @1:1-1:1 = use move %0 @2:1-2:1 @1:1-1:1
              goto bb2
            bb2:
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [
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
              %2 @2:1-2:1 = use 1 @1:1-1:1
              declare %0
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              %0 @1:1-1:1 = use 1 @1:1-1:1
              goto bb1
            bb3:
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(.usedUninitialized(name: "x"), at: at(2))])
    }

    @Test func `a 'var' may be assigned any number of times, and a 'let' only once on each path`() throws {
        let blocks = """
            bb0:
              declare %0
              %0 @1:1-1:1 = use 1 @1:1-1:1
              %0 @1:1-1:1 = use 2 @1:1-1:1
              declare %2
              %2 @2:1-2:1 = use 1 @1:1-1:1
              %2 @2:2-2:2 = use 2 @1:1-1:1
              %2 @2:3-2:3 = use 3 @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [
            Diagnostic(.letAssignedTwice(name: "k"), at: at(2)), Diagnostic(.letAssignedTwice(name: "k"), at: at(3)),
        ])
    }

    @Test func `a 'let' that a move left without a value was still assigned, so it can't be assigned again`() throws {
        let blocks = """
            bb0:
              declare %2
              %2 @1:1-1:1 = use 1 @1:1-1:1
              %1 @1:1-1:1 = use move %2 @2:1-2:1 @1:1-1:1
              %2 @2:2-2:2 = use 2 @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(.letAssignedTwice(name: "k"), at: at(2))])
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
              %2 @2:1-2:1 = use 1 @1:1-1:1
              goto bb1
            bb3:
              return
            """ : """
            bb0:
              declare %2
              branch true, bb1, bb2
            bb1:
              %2 @1:1-1:1 = use 1 @1:1-1:1
              goto bb2
            bb2:
              %2 @2:1-2:1 = use 2 @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(.letMaybeAssignedTwice(name: "k"), at: at(1))])
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
        #expect(try errors(in: blocks) == [
            Diagnostic(.usedUninitialized(name: "x"), at: at(1)), Diagnostic(.usedUninitialized(name: "y"), at: at(3)),
        ])
    }

    @Test(arguments: [
        ("declare %5", ErrorCode.usedUninitialized(name: "s"), []),
        (storeShot() + "\n  _ = use move %5 @2:1-2:1 @1:1-1:1", .usedAfterMove(name: "s"), [1]),
    ])
    func `a store to a field uses its local, which must hold the rest of its value`(
        before: String, expected: ErrorCode, moveColumns: [Int],
    ) throws {
        let blocks = """
            bb0:
            \(before)
              %5.1.0 @2:2-2:2 = use 9 @1:1-1:1
              _ = use read %5 @2:3-2:3 @1:1-1:1
              return
            """
        // The read after the store has the same cause as the store, so the store alone is reported.
        #expect(try errors(in: blocks) == [Diagnostic(expected, at: at(2), labeling: moves(at: moveColumns))])
    }

    @Test func `a store to a field leaves its local holding its value, which a move may then take`() throws {
        let blocks = """
            bb0:
            \(storeShot())
              %5.0 @2:1-2:1 = use 9 @1:1-1:1
              _ = use move %5 @2:2-2:2 @1:1-1:1
              _ = use read %5 @2:3-2:3 @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(.usedAfterMove(name: "s"), at: at(3), labeling: moves(at: [2]))])
    }

    @Test func `the errors come in source order across the program's functions`() throws {
        // The first function's error comes after the second's in the source.
        let usesLate = function("""
            bb0:
              %0 @1:1-1:1 = use 1 @1:1-1:1
              %1 @1:1-1:1 = use move %0 @2:1-2:1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:6-2:6) @1:1-1:1
              return
            """, named: "late()")
        let usesEarly = function("""
            bb0:
              %0 @1:1-1:1 = use 1 @1:1-1:1
              %1 @1:1-1:1 = use move %0 @2:2-2:2 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:5-2:5) @1:1-1:1
              return
            """, named: "early()")

        // The checker reports the second function's error first, as the source has it.
        let reported = InitializationChecker.check(try program(of: [usesLate, usesEarly]))
        #expect(reported.map(\.range.start.column) == [5, 6])
    }
}

struct FieldMoveTests {
    @Test func `a field moved out of a local leaves its other fields readable, and itself unreadable`() throws {
        let blocks = """
            bb0:
            \(storeShot())
              %4 @1:1-1:1 = use move %5.1 @2:1-2:1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %5.0 @2:2-2:2) @1:1-1:1
              _ = call builtin "print(_: Int)"(read %5.1.0 @2:3-2:3) @1:1-1:1
              _ = use read %4 @2:4-2:4 @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [
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
              _ = use move \(moved) @2:1-2:1 @1:1-1:1
              _ = use \(use) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(expected, at: at(2), labeling: moves(at: [1]))])
    }

    @Test(arguments: [("%5.1", "%5.1"), ("%5.1.0", "%5.1.0"), ("%5.1.0", "%5.1")])
    func `assigning a moved field, or a field that holds it, makes the local whole again`(
        moved: String, assigned: String,
    ) throws {
        // A `Hit` replaces a moved `hit`, and an Int its `damage`.
        let newValue = assigned == "%5.1" ? "struct Hit(3)" : "use 3"
        let blocks = """
            bb0:
            \(storeShot())
              _ = use move \(moved) @2:1-2:1 @1:1-1:1
              \(assigned) @2:2-2:2 = \(newValue) @1:1-1:1
              _ = use move %5 @2:3-2:3 @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [])
    }

    @Test func `a field is assigned only where the field that holds it holds a value`() throws {
        let blocks = """
            bb0:
            \(storeShot())
              _ = use move %5.1 @2:1-2:1 @1:1-1:1
              %5.1.0 @2:2-2:2 = use 3 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %5.1.0 @2:3-2:3) @1:1-1:1
              return
            """
        // The read has the same cause as the store, so the store alone is reported.
        #expect(try errors(in: blocks) == [
            Diagnostic(.usedAfterMove(name: "s.hit"), at: at(2), labeling: moves(at: [1])),
        ])
    }

    @Test func `assigning the whole local after a field was moved out of it makes it whole again`() throws {
        let blocks = """
            bb0:
            \(storeShot())
              _ = use move %5.1 @2:1-2:1 @1:1-1:1
            \(storeShot(at: 2))
              _ = call builtin "print(_: Int)"(read %5.1.0 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [])
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
              _ = use move %5.1 @2:1-2:1 @1:1-1:1
              goto bb2
            bb2:
              _ = use \(use) @1:1-1:1
              return
            """
        let expectedErrors = expected.map { [Diagnostic($0, at: at(2), labeling: moves(at: [1]))] }
        #expect(try errors(in: blocks) == expectedErrors ?? [])
    }

    @Test func `a field moved on every path that joins was moved`() throws {
        let blocks = """
            bb0:
            \(storeShot())
              branch true, bb1, bb2
            bb1:
              _ = use move %5.1 @2:1-2:1 @1:1-1:1
              goto bb3
            bb2:
              _ = use move %5.1 @2:2-2:2 @1:1-1:1
              goto bb3
            bb3:
              _ = call builtin "print(_: Int)"(read %5.1.0 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [
            Diagnostic(.usedAfterMove(name: "s.hit"), at: at(3), labeling: moves(at: [1, 2])),
        ])
    }
}

/// The moves at `columns`, each labeled as a move, as an error notes the moves that caused it.
private func moves(at columns: [Int]) -> [Diagnostic.LabeledRange] {
    columns.map { Diagnostic.LabeledRange(.moved, at: at($0)) }
}

/// The errors the checker reports in a program of one function made of `blocks`, which returns `result` and whose
/// parameters are of `parameters`' types.
private func errors(in blocks: String, parameters: String = "", result: String = "Void") throws -> [Diagnostic] {
    InitializationChecker.check(try program(of: [function(blocks, parameters: parameters, result: result)]))
}
