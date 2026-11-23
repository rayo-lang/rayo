import RayoOwnership
import Testing
import RayoDiagnostics
import RayoIR
import RayoCheckedProgram

struct UnusedValueCheckerTests {
    @Test func `a value stored in a local that no code reads is reported at the store`() throws {
        let blocks = "bb0:\n  declare %2\n  %2 @2:1-2:1 = operand 1 @1:1-1:1\n  return"
        #expect(try checked(function(blocks)).errors == [Diagnostic(.unreadValue(name: "k"), at: at(1))])
    }

    @Test
    func `a value that an assignment overwrites before any code reads it is reported, and the new one isn't`() throws {
        let blocks = """
            bb0:
              %0 @2:1-2:1 = operand 1 @1:1-1:1
              %0 @2:2-2:2 = operand 2 @1:1-1:1
              begin a0 read %0 @2:3-2:3
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [Diagnostic(.unreadValue(name: "x"), at: at(1))])
    }

    @Test func `a value read on one of the paths from its store is used, though another path overwrites it`() throws {
        let blocks = """
            bb0:
              %0 @2:1-2:1 = operand 1 @1:1-1:1
              branch true, bb1, bb2
            bb1:
              begin a0 read %0 @2:2-2:2
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:1
              goto bb2
            bb2:
              %0 @2:3-2:3 = operand 2 @1:1-1:1
              _ = operand move %0 @2:4-2:4 @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test(arguments: [
        (true, [Diagnostic]()),
        (false, [Diagnostic(.unreadValue(name: "x"), at: at(1)), Diagnostic(.unreadValue(name: "x"), at: at(2))]),
    ])
    func `a value stored in a loop's body is used when the next pass reads it`(
        bodyReads: Bool, expected: [Diagnostic],
    ) throws {
        let value = bodyReads ? "add checked read %0 @2:3-2:3, 1" : "operand 1"
        let blocks = """
            bb0:
              %0 @2:1-2:1 = operand 0 @1:1-1:1
              goto bb1
            bb1:
              branch true, bb2, bb3
            bb2:
              %0 @2:2-2:2 = \(value) @1:1-1:1
              goto bb1
            bb3:
              return
            """
        #expect(try checked(function(blocks)).errors == expected)
    }

    @Test func `a branch's condition and a return's result read the locals they name`() throws {
        let blocks = """
            bb0:
              %6 @1:1-1:1 = operand true @1:1-1:1
              branch read %6 @2:1-2:1, bb1, bb1
            bb1:
              %1 @1:1-1:1 = operand 2 @1:1-1:1
              return move %1 @2:2-2:2
            """
        #expect(try checked(function(blocks, result: "Int")).errors == [])
    }

    @Test func `a declaration starts its local's life, so a read after it reads no value stored before it`() throws {
        let blocks = """
            bb0:
              %0 @2:1-2:1 = operand 1 @1:1-1:1
              declare %0
              %0 @1:1-1:1 = operand 2 @1:1-1:1
              begin a0 read %0 @2:2-2:2
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [Diagnostic(.unreadValue(name: "x"), at: at(1))])
    }

    @Test func `a temporary that no code reads reports nothing, since lowering made it`() throws {
        #expect(try checked(function("bb0:\n  %3 @1:1-1:1 = operand 1 @1:1-1:1\n  return")).errors == [])
    }

    @Test func `a block that no path reaches reports nothing`() throws {
        let blocks = """
            bb0:
              return
            bb1:
              %0 @2:1-2:1 = operand 1 @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [])
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
              %5.1.0 @2:2-2:2 = operand 9 @1:1-1:1
              _ = operand \(later) @1:1-1:1
              begin a0 read %5.0 @2:4-2:4
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == expected)
    }

    @Test func `a store to a field leaves the struct's other fields as they were, which a later read still reads`()
        throws {
        let blocks = """
            bb0:
            \(storeShot(at: 1))
              %5.0 @2:2-2:2 = operand 9 @1:1-1:1
              begin a0 read %5.1.0 @2:3-2:3
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:1
              begin a1 read %5.0 @2:4-2:4
              _ = call builtin "print(_: &Int)"(a1) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test(arguments: [
        ("%5.0", "operand 9", "s.range"),
        ("%5.1.0", "operand 9", "s.hit.damage"),
        ("%5.1", "call \"Hit(damage: Int)\"(9)", "s.hit"),
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
              _ = operand move %5 @2:4-2:4 @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [Diagnostic(.unreadValue(name: path), at: at(2))])
    }

    @Test func `a struct's value is never read when each of its fields that code reads is replaced first`() throws {
        let blocks = """
            bb0:
            \(storeShot(at: 1))
              %5.0 @2:2-2:2 = operand 9 @1:1-1:1
              begin a0 read %5.0 @2:3-2:3
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [Diagnostic(.unreadValue(name: "s"), at: at(1))])
    }

    @Test(arguments: [
        // A read of the other element reads what the array was filled with there, but not the store.
        (["_ = operand read %7[1].0 @1:1-1:1 @1:1-1:1"], "a[0]", 2),
        // A store to the same element replaces the first store's value before any code reads it.
        (
            [#"%7[0] @1:1-1:1 = call "Hit(damage: Int)"(4) @1:1-1:1"#, "_ = operand read %7 @1:1-1:1 @1:1-1:1"],
            "a[0]", 2,
        ),
        // A store to each element replaces the whole of what the array was filled with.
        (
            [#"%7[1] @1:1-1:1 = call "Hit(damage: Int)"(4) @1:1-1:1"#, "_ = operand read %7 @1:1-1:1 @1:1-1:1"],
            "a", 1,
        ),
    ])
    func `a value stored in an element is read by a later read of the element, or of the array`(
        later: [String], name: String, column: Int,
    ) throws {
        let laterLines = later.map { "  \($0)" }.joined(separator: "\n")
        let blocks = """
            bb0:
              %4 @1:1-1:1 = call "Hit(damage: Int)"(7) @1:1-1:1
              %7 @2:1-2:1 = fill 2 of read %4 @1:1-1:1 @1:1-1:1
              %7[0] @2:2-2:2 = call "Hit(damage: Int)"(9) @1:1-1:1
            \(laterLines)
              return
            """
        #expect(try checked(function(blocks)).errors == [Diagnostic(.unreadValue(name: name), at: at(column))])
    }

    @Test func `a value stored in an element, and one a compound assignment stores in a part of it, are read later`()
        throws {
        // As `a[0] = Hit(damage: 9)`, then `a[0].damage += 1`, then a read of each element.
        let blocks = """
            bb0:
              %4 @1:1-1:1 = call "Hit(damage: Int)"(7) @1:1-1:1
              %7 @2:1-2:1 = fill 2 of read %4 @1:1-1:1 @1:1-1:1
              %7[0] @2:2-2:2 = call "Hit(damage: Int)"(9) @1:1-1:1
              %7[0].0 @2:3-2:3 = add checked read %7[0].0 @1:1-1:1, 1 @1:1-1:1
              begin a0 read %7[0].0 @1:1-1:1
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:1
              begin a1 read %7[1].0 @1:1-1:1
              _ = call builtin "print(_: &Int)"(a1) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test func `a compound assignment reads the value it replaces, and stores one that code must read`() throws {
        // As `x += 1` lowers, after a read of `x`, and with nothing after it.
        let blocks = """
            bb0:
              %0 @2:1-2:1 = operand 1 @1:1-1:1
              begin a0 read %0 @1:1-1:1
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:1
              %0 @2:2-2:2 = add checked read %0 @1:1-1:1, 1 @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [Diagnostic(.unreadValue(name: "x"), at: at(2))])
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        // Each store is read by the borrow of the whole array after it, through the call.
        (
            [
                "%0[0] @1:1-1:1 = operand 1 @1:1-1:1", "begin a0 read %0 @1:1-1:1", totalOfArray("a0"),
                "%0[%1] @1:1-1:1 = operand 2 @1:1-1:1", "begin a1 read %0 @1:1-1:1", totalOfArray("a1"),
                "%0[0] @1:1-1:1 = add checked read %0[0] @1:1-1:1, 3 @1:1-1:1",
                "begin a2 read %0 @1:1-1:1", totalOfArray("a2"),
            ],
            [Diagnostic](),
        ),
        // A later store to the same element replaces the first one's value before the borrow reads it.
        (
            [
                "%0[0] @2:1-2:1 = operand 1 @1:1-1:1", "%0[0] @1:1-1:1 = operand 2 @1:1-1:1",
                "begin a0 read %0 @1:1-1:1", totalOfArray("a0"),
            ],
            [Diagnostic(.unreadValue(name: "a[0]"), at: at(1))],
        ),
    ])
    func `an element of an array of a billion is stored to and borrowed in the time a small array takes`(
        statements: [String], expected: [Diagnostic],
    ) throws {
        // `%1` holds an index that may be any element's, so a store through it may reach any of them.
        let body = statements.map { "  \($0)" }.joined(separator: "\n")
        let huge = (name: "f()", text: """
            func "f()"() -> Void {
              var %0 a: [1000000000 of Int] @1:1-1:1
              temp %1: UInt
            bb0:
              %0 @1:1-1:1 = fill 1000000000 of 0 @1:1-1:1
              %1 @1:1-1:1 = index UInt 5 below 1000000000 @1:1-1:1
            \(body)
              return
            }
            """)
        #expect(try checked(huge, beside: [totalOfHuge]).errors == expected)
    }

    @Test(.timeLimit(.minutes(1)))
    func `stores to a different element on each of many paths are checked in the time one path takes`() throws {
        // As `if … { a[i] = 0 }` for each index `i` below the branch count, then a borrow of the whole array. The paths
        // store to 2^24 different sets of elements, and the borrow reads each of them.
        let branchCount = 24
        let conditionalStores = (0..<branchCount).map { index in
            """
            bb\(2 * index + 1):
              branch true, bb\(2 * index + 2), bb\(2 * index + 3)
            bb\(2 * index + 2):
              %0[\(index)] @1:1-1:1 = operand 0 @1:1-1:1
              goto bb\(2 * index + 3)
            """
        }
        let stores = (name: "f()", text: """
            func "f()"() -> Void {
              var %0 a: [32 of Int] @1:1-1:1
            bb0:
              %0 @1:1-1:1 = fill 32 of 0 @1:1-1:1
              goto bb1
            \(conditionalStores.joined(separator: "\n"))
            bb\(2 * branchCount + 1):
              begin a0 read %0 @1:1-1:1
              _ = call "use(_: [32 of Int])"(a0) @1:1-1:1
              return
            }
            """)
        let use = (name: "use(_: [32 of Int])", text: #"func "use(_: [32 of Int])"(_: &[32 of Int]) -> Int"#)
        #expect(try checked(stores, beside: [use]).errors == [])
    }

    @Test func `a store to an element at an index a local holds leaves a later read through that local reading`()
        throws {
        // The temporary holds a new index by the time the read goes through it, so the read may reach an element the
        // store left as the first store to `a` made it.
        let blocks = """
            bb0:
              %4 @1:1-1:1 = call "Hit(damage: Int)"(7) @1:1-1:1
              %7 @2:1-2:1 = array of Hit(read %4 @1:1-1:1, read %4 @1:1-1:1) @1:1-1:1
              %8 @1:1-1:1 = index UInt 0 below 2 @1:1-1:1
              %7[%8] @2:2-2:2 = call "Hit(damage: Int)"(9) @1:1-1:1
              %8 @1:1-1:1 = index UInt 1 below 2 @1:1-1:1
              begin a0 read %7[%8].0 @2:3-2:3
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test func `a value assigned to a mutable parameter is read at every return, since its caller reads it`() throws {
        let blocks = """
            bb0:
              branch true, bb1, bb2
            bb1:
              %0 @2:1-2:1 = operand 1 @1:1-1:1
              return
            bb2:
              %0 @2:2-2:2 = operand 2 @1:1-1:1
              return
            """
        #expect(try checked(taking("mutable &Int", blocks)).errors == [])
    }

    @Test(arguments: [
        (#"begin a0 read %0 @1:1-1:1\#n  _ = call builtin "print(_: &Int)"(a0) @1:1-1:1"#, [Diagnostic]()),
        ("_ = operand 1 @1:1-1:1", [Diagnostic(.unreadParameter(name: "n"), at: at(1))]),
    ])
    func `an owned parameter that no code reads is reported where it is declared`(
        statement: String, expected: [Diagnostic],
    ) throws {
        #expect(try checked(taking("Int", "bb0:\n  \(statement)\n  return")).errors == expected)
    }

    @Test func `a borrowed parameter that no code reads is not reported`() throws {
        #expect(try checked(taking("&Int", "bb0:\n  return")).errors == [])
    }
}

/// The function `f(_: Int)`, made of `blocks`, whose one local is its parameter `n` (`%0`), of `parameter`, the
/// parameter's convention and type, which the source declares at column 1 of line 2.
private func taking(_ parameter: String, _ blocks: String) -> (name: String, text: String) {
    let text = """
        func "f(_: Int)"(_: \(parameter)) -> Void {
          param %0 n: \(parameter) @2:1-2:1
        \(blocks)
        }
        """
    return ("f(_: Int)", text)
}

/// A function that takes an array of a billion Ints and gives an Int, which has no body.
private let totalOfHuge = (
    name: "total(_: [1000000000 of Int])",
    text: #"func "total(_: [1000000000 of Int])"(_: &[1000000000 of Int]) -> Int"#,
)

/// The statement that passes the array of a billion Ints, through the access `access`, to `total`.
private func totalOfArray(_ access: String) -> String {
    #"_ = call "total(_: [1000000000 of Int])"(\#(access)) @1:1-1:1"#
}
