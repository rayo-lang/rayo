import Testing
import RayoDiagnostics
import RayoIR
import RayoOwnership
import RayoSema

struct UnusedValueCheckerTests {
    @Test func `a value stored in a local that no code reads is reported at the store`() throws {
        let blocks = "bb0:\n  declare %2\n  %2 @2:1-2:1 = use 1 @1:1-1:1\n  return"
        #expect(try errors(in: blocks) == [Diagnostic(.unreadValue(name: "k"), at: at(1))])
    }

    @Test
    func `a value that an assignment overwrites before any code reads it is reported, and the new one isn't`() throws {
        let blocks = """
            bb0:
              %0 @2:1-2:1 = use 1 @1:1-1:1
              %0 @2:2-2:2 = use 2 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(.unreadValue(name: "x"), at: at(1))])
    }

    @Test func `a value read on one of the paths from its store is used, though another path overwrites it`() throws {
        let blocks = """
            bb0:
              %0 @2:1-2:1 = use 1 @1:1-1:1
              branch true, bb1, bb2
            bb1:
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              goto bb2
            bb2:
              %0 @2:3-2:3 = use 2 @1:1-1:1
              _ = call builtin "print(_: Int)"(move %0 @2:4-2:4) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [])
    }

    @Test(arguments: [
        (true, [Diagnostic]()),
        (false, [Diagnostic(.unreadValue(name: "x"), at: at(1)), Diagnostic(.unreadValue(name: "x"), at: at(2))]),
    ])
    func `a value stored in a loop's body is used when the next pass reads it`(
        bodyReads: Bool, expected: [Diagnostic],
    ) throws {
        let value = bodyReads ? "add checked read %0 @2:3-2:3, 1" : "use 1"
        let blocks = """
            bb0:
              %0 @2:1-2:1 = use 0 @1:1-1:1
              goto bb1
            bb1:
              branch true, bb2, bb3
            bb2:
              %0 @2:2-2:2 = \(value) @1:1-1:1
              goto bb1
            bb3:
              return
            """
        #expect(try errors(in: blocks) == expected)
    }

    @Test func `a branch's condition and a return's result read the locals they name`() throws {
        let blocks = """
            bb0:
              %6 @1:1-1:1 = use true @1:1-1:1
              branch read %6 @2:1-2:1, bb1, bb1
            bb1:
              %1 @1:1-1:1 = use 2 @1:1-1:1
              return move %1 @2:2-2:2
            """
        #expect(try errors(in: blocks, result: "Int") == [])
    }

    @Test func `a declaration starts its local's life, so a read after it reads no value stored before it`() throws {
        let blocks = """
            bb0:
              %0 @2:1-2:1 = use 1 @1:1-1:1
              declare %0
              _ = call builtin "print(_: Int)"(read %0 @2:2-2:2) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(.unreadValue(name: "x"), at: at(1))])
    }

    @Test func `a temporary that no code reads reports nothing, since lowering made it`() throws {
        #expect(try errors(in: "bb0:\n  %3 @1:1-1:1 = use 1 @1:1-1:1\n  return") == [])
    }

    @Test func `a block that no path reaches reports nothing`() throws {
        let blocks = """
            bb0:
              return
            bb1:
              %0 @2:1-2:1 = use 1 @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [])
    }

    @Test(arguments: [
        ("read %5 @2:3-2:3", [Diagnostic]()),
        ("read %5.1 @2:3-2:3", []),
        ("read %5.1.0 @2:3-2:3", []),
        ("read %5.0 @2:3-2:3", [Diagnostic(.unreadValue(name: "s.hit.damage"), at: at(2))]),
    ])
    func `a value stored in a field is read by a later read of the field, or of a struct that holds it`(
        later: String, expected: [Diagnostic],
    ) throws {
        // The last read, of `range`, reads the Shot that `s` is given, so only the store to `damage` may go unread.
        let blocks = """
            bb0:
            \(storeShot(at: 1))
              %5.1.0 @2:2-2:2 = use 9 @1:1-1:1
              _ = use \(later) @1:1-1:1
              _ = call builtin "print(_: Int)"(read %5.0 @2:4-2:4) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == expected)
    }

    @Test func `a store to a field leaves the struct's other fields as they were, which a later read still reads`()
        throws {
        let blocks = """
            bb0:
            \(storeShot(at: 1))
              %5.0 @2:2-2:2 = use 9 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %5.1.0 @2:3-2:3) @1:1-1:1
              _ = call builtin "print(_: Int)"(read %5.0 @2:4-2:4) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [])
    }

    @Test(arguments: [
        ("%5.0", "use 9", "s.range"),
        ("%5.1.0", "use 9", "s.hit.damage"),
        ("%5.1", "struct Hit(9)", "s.hit"),
    ])
    func `a later read of the whole struct doesn't read a field's value that a store replaced before it`(
        field: String, value: String, path: String,
    ) throws {
        // The struct's other fields keep the values the first store to `s` gave them, which the move reads.
        let blocks = """
            bb0:
            \(storeShot(at: 1))
              \(field) @2:2-2:2 = \(value) @1:1-1:1
              \(field) @2:3-2:3 = \(value) @1:1-1:1
              _ = use move %5 @2:4-2:4 @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(.unreadValue(name: path), at: at(2))])
    }

    @Test func `a struct's value is never read when each of its fields that code reads is replaced first`() throws {
        let blocks = """
            bb0:
            \(storeShot(at: 1))
              %5.0 @2:2-2:2 = use 9 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %5.0 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(.unreadValue(name: "s"), at: at(1))])
    }

    @Test func `each function's errors come under its ID, and a function without any has none`() throws {
        // The first function's error comes after the second's in the source.
        let late = function("bb0:\n  %0 @2:6-2:6 = use 1 @1:1-1:1\n  return", named: "late()")
        let early = function("bb0:\n  %0 @2:5-2:5 = use 1 @1:1-1:1\n  return", named: "early()")

        let clean = function("bb0:\n  return", named: "clean()")

        let reported = UnusedValueChecker.check(try program(of: [late, early, clean]))
        #expect(reported.mapValues { $0.map(\.range.start.column) } == [
            FunctionID(index: 0): [6], FunctionID(index: 1): [5],
        ])
    }
}

/// The errors the checker reports in a program of one function, which returns `result` and is made of `blocks`.
private func errors(in blocks: String, result: String = "Void") throws -> [Diagnostic] {
    UnusedValueChecker.check(try program(of: [function(blocks, result: result)]))[FunctionID(index: 0)] ?? []
}
