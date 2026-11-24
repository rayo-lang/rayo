import RayoOwnership
import RayoDiagnostics
import RayoIR
import RayoCheckedProgram
import Testing

@Suite("Where accesses end, and which of them conflict")
struct AccessExtentTests {
    @Test func `a modify access and a read access of one place, live across one call, conflict`() throws {
        // As `change(&x, x)` lowers: the modify access is still live where the read access begins.
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 modify %0 @2:3-2:3
              begin a1 read %0 @2:6-2:6
              _ = call "change(_: mutable &Int, _: &Int)"(a0, a1) @1:1-1:1
              return
            """
        let expected = Diagnostic(
            .usedWhileMutablyBorrowed(name: "x", borrowed: "x"), at: at(6), labeling: [.init(.borrowed, at: at(3))],
        )
        #expect(try checked(function(blocks)).errors == [expected])
    }

    @Test func `accesses to two fields of one value don't conflict, whatever they do`() throws {
        // As `take(&s.range, s.hit)` lowers.
        let blocks = """
            bb0:
            \(storeShot())
              begin a0 modify %5.0 @2:3-2:3
              begin a1 read %5.1 @2:6-2:6
              _ = call "change(_: mutable &Int, _: &Hit)"(a0, a1) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test func `accesses to two elements at different indices the IR writes don't conflict, whatever they do`() throws {
        // As `take(&a[0].damage, a[1])` lowers.
        let blocks = """
            bb0:
              %4 @1:1-1:1 = call "Hit(damage: Int)"(7) @1:1-1:1
              %7 @1:1-1:1 = fill 2 of read %4 @1:1-1:1 @1:1-1:1
              begin a0 modify %7[0].0 @2:3-2:3
              begin a1 read %7[1] @2:6-2:6
              _ = call "change(_: mutable &Int, _: &Hit)"(a0, a1) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test(arguments: [
        ("%7[%8].0", "%7[1]", ErrorCode.usedWhileMutablyBorrowed(name: "a[1]", borrowed: "a")),
        ("%7[1].0", "%7[%8]", .usedWhileMutablyBorrowed(name: "a", borrowed: "a[1].damage")),
        ("%7[0].0", "%7[0]", .usedWhileMutablyBorrowed(name: "a[0]", borrowed: "a[0].damage")),
    ])
    func `accesses to two elements of one array conflict, unless the IR writes both indices and they differ`(
        modified: String, read: String, code: ErrorCode,
    ) throws {
        // As `take(&a[i].damage, a[1])` lowers, where the local `%8` holds `i`'s value.
        let blocks = """
            bb0:
              %4 @1:1-1:1 = call "Hit(damage: Int)"(7) @1:1-1:1
              %7 @1:1-1:1 = fill 2 of read %4 @1:1-1:1 @1:1-1:1
              %8 @1:1-1:1 = index UInt 1 below 2 @1:1-1:1
              begin a0 modify \(modified) @2:3-2:3
              begin a1 read \(read) @2:6-2:6
              _ = call "change(_: mutable &Int, _: &Hit)"(a0, a1) @1:1-1:1
              return
            """
        let expected = Diagnostic(code, at: at(6), labeling: [.init(.borrowed, at: at(3))])
        #expect(try checked(function(blocks)).errors == [expected])
    }

    @Test func `two read accesses of one place don't conflict`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read %0 @2:3-2:3
              begin a1 read %0 @2:6-2:6
              _ = call "g(_: &Int, _: &Int)"(a0, a1) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test(arguments: [
        // An assignment to a value that holds the place, or to a field inside it, changes what the access reads.
        ("%5 @2:6-2:6 = operand read %5 @1:1-1:1 @1:1-1:1", ErrorCode.changedWhileBorrowed(name: "s", borrowed: "s.hit")),
        ("%5.1.0 @2:6-2:6 = operand 3 @1:1-1:1", .changedWhileBorrowed(name: "s.hit.damage", borrowed: "s.hit")),
        // So does a move out of the place.
        ("%4 @1:1-1:1 = operand move %5.1 @2:6-2:6 @1:1-1:1", .movedWhileBorrowed(name: "s.hit", borrowed: "s.hit")),
    ])
    func `a change to a place that a live read access overlaps conflicts with it`(
        change: String, code: ErrorCode,
    ) throws {
        let blocks = """
            bb0:
            \(storeShot())
              begin a0 read %5.1 @2:3-2:3
              \(change)
              _ = call "take(_: &Int, _: &Hit)"(1, a0) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [
            Diagnostic(code, at: at(6), labeling: [.init(.borrowed, at: at(3))]),
        ])
    }

    @Test func `a move inside a call conflicts with a borrow that an access the call passes depends on`() throws {
        // `r` borrows `h`, so the access to `r.damage` that the call passes keeps the borrow live at the call's move.
        let blocks = """
              begin a1 read %1.0 @2:6-2:6
              _ = call "pair(_: &Int, _: Int)"(a1, move %0.0 @2:9-2:9) @1:1-1:1
            """
        #expect(try checked(borrowingHit(then: blocks), beside: [pair]).errors == [damageMovedWhileBorrowed])
    }

    @Test func `a move inside a call conflicts with a borrow that a value the call reads next depends on`() throws {
        // The call moves `h.damage` out, and then reads `r.damage`, whose value depends on the borrow of `h`.
        let blocks = """
              _ = call "sum(_: Int, _: Int)"(move %0.0 @2:9-2:9, read %1.0 @1:1-1:1) @1:1-1:1
            """
        let sum = (name: "sum(_: Int, _: Int)", text: #"func "sum(_: Int, _: Int)"(_: Int, _: Int) -> Void"#)
        #expect(try checked(borrowingHit(then: blocks), beside: [sum]).errors == [damageMovedWhileBorrowed])
    }

    @Test func `a move before a call conflicts with a borrow that an access the call passes depends on`() throws {
        // The same move in a statement of its own, before the access to `r.damage` begins.
        let blocks = """
              %2 @1:1-1:1 = operand move %0.0 @2:9-2:9 @1:1-1:1
              begin a1 read %1.0 @2:6-2:6
              _ = call "pair(_: &Int, _: Int)"(a1, move %2 @1:1-1:1) @1:1-1:1
            """
        #expect(try checked(borrowingHit(then: blocks), beside: [pair]).errors == [damageMovedWhileBorrowed])
    }

    @Test(arguments: [
        // The move and the store in one statement, and the move in a statement of its own before the store.
        "%1.0 @1:1-1:1 = operand move %0.0 @2:9-2:9 @1:1-1:1",
        """
        %2 @1:1-1:1 = operand move %0.0 @2:9-2:9 @1:1-1:1
          %1.0 @1:1-1:1 = operand move %2 @1:1-1:1 @1:1-1:1
        """,
    ])
    func `a move conflicts with no borrow once a store replaces all that later code reads of the dependent value`(
        moveAndStore: String,
    ) throws {
        // The store replaces `r.damage`, the one part of `r` read later, so nothing reads what `r` borrowed of `h`.
        let blocks = """
              \(moveAndStore)
              %2 @1:1-1:1 = operand read %1.0 @1:1-1:1 @1:1-1:1
            """
        let errors = try checked(borrowingHit(then: blocks)).errors
        #expect(!errors.contains(damageMovedWhileBorrowed))
    }

    @Test func `a read of a place that a live modify access overlaps conflicts with it`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 modify %0 @2:3-2:3
              %1 @1:1-1:1 = operand read %0 @2:6-2:6 @1:1-1:1
              _ = call "change(_: mutable &Int, _: &Int)"(a0, 1) @1:1-1:1
              return
            """
        let expected = Diagnostic(
            .usedWhileMutablyBorrowed(name: "x", borrowed: "x"), at: at(6), labeling: [.init(.borrowed, at: at(3))],
        )
        #expect(try checked(function(blocks)).errors == [expected])
    }

    @Test func `a change to a place before an access to it begins conflicts with none`() throws {
        // As `g(x, if x > 0 { x = 2; 1 } else { 3 })` lowers: a branch of the second argument assigns `x` before the
        // call's accesses begin.
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              %6 @1:1-1:1 = greater read %0 @1:1-1:1, 0 @1:1-1:1
              branch read %6 @1:1-1:1, bb1, bb2
            bb1:
              %0 @2:1-2:1 = operand 2 @1:1-1:1
              %3 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb3
            bb2:
              %3 @1:1-1:1 = operand 3 @1:1-1:1
              goto bb3
            bb3:
              begin a0 read %0 @2:3-2:3
              begin a1 read %3 @1:1-1:1
              _ = call "g(_: &Int, _: &Int)"(a0, a1) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test func `a change after an access's last use, or a store of what its call gives, conflicts with none`() throws {
        // As `x = double(x)` lowers, then a change to `x` once nothing uses the access.
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read %0 @2:3-2:3
              %0 @2:5-2:5 = call "double(_: &Int)"(a0) @1:1-1:1
              begin a1 read %0 @1:1-1:1
              _ = call builtin "print(_: &Int)"(a1) @1:1-1:1
              %0 @2:6-2:6 = operand 2 @1:1-1:1
              begin a2 read %0 @1:1-1:1
              _ = call "g(_: &Int, _: &Int)"(a2, 2) @1:1-1:1
              return
            """
        #expect(try checked(function(blocks)).errors == [])
    }

    @Test func `an access ends after its last use, the latest begun first`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read %0 @1:1-1:1
              begin a1 read %0 @1:1-1:1
              _ = call "g(_: &Int, _: &Int)"(a0, a1) @1:1-1:1
              _ = call "g(_: &Int, _: &Int)"(1, 2) @1:1-1:1
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read %0 @1:1-1:1
              begin a1 read %0 @1:1-1:1
              _ = call "g(_: &Int, _: &Int)"(a0, a1) @1:1-1:1
              end a1
              end a0
              _ = call "g(_: &Int, _: &Int)"(1, 2) @1:1-1:1
              return
            """))
    }

    @Test func `an access that nothing uses ends where it begins`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read %0 @1:1-1:1
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read %0 @1:1-1:1
              end a0
              return
            """))
    }

    @Test func `an access live into one branch only ends there after its use, and as the other branch starts`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read %0 @1:1-1:1
              branch true, bb1, bb2
            bb1:
              _ = call "g(_: &Int, _: &Int)"(a0, 1) @1:1-1:1
              goto bb3
            bb2:
              goto bb3
            bb3:
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read %0 @1:1-1:1
              branch true, bb1, bb2
            bb1:
              _ = call "g(_: &Int, _: &Int)"(a0, 1) @1:1-1:1
              end a0
              goto bb3
            bb2:
              end a0
              goto bb3
            bb3:
              return
            """))
    }

    @Test func `an access left on the way into a block that other paths enter ends in a block on that way`() throws {
        // `bb1` also enters `bb2`, having ended the access, so `bb0`'s way into `bb2` gets a block that ends it.
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read %0 @1:1-1:1
              branch true, bb1, bb2
            bb1:
              _ = call "g(_: &Int, _: &Int)"(a0, 1) @1:1-1:1
              goto bb2
            bb2:
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read %0 @1:1-1:1
              branch true, bb1, bb3
            bb1:
              _ = call "g(_: &Int, _: &Int)"(a0, 1) @1:1-1:1
              end a0
              goto bb2
            bb2:
              return
            bb3:
              end a0
              goto bb2
            """))
    }

    @Test func `an access left on the way back into the first block ends in a block on that way`() throws {
        // The function's entry enters `bb0` too, without the access, so `bb1`'s way back gets a block that ends it.
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb1
            bb1:
              begin a0 read %0 @1:1-1:1
              branch true, bb0, bb2
            bb2:
              _ = call "g(_: &Int, _: &Int)"(a0, 1) @1:1-1:1
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb1
            bb1:
              begin a0 read %0 @1:1-1:1
              branch true, bb3, bb2
            bb2:
              _ = call "g(_: &Int, _: &Int)"(a0, 1) @1:1-1:1
              end a0
              return
            bb3:
              end a0
              goto bb0
            """))
    }

    @Test func `an access begun in a loop's body ends in the body, on each pass`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb1
            bb1:
              branch true, bb2, bb3
            bb2:
              begin a0 read %0 @1:1-1:1
              _ = call "g(_: &Int, _: &Int)"(a0, 1) @1:1-1:1
              goto bb1
            bb3:
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb1
            bb1:
              branch true, bb2, bb3
            bb2:
              begin a0 read %0 @1:1-1:1
              _ = call "g(_: &Int, _: &Int)"(a0, 1) @1:1-1:1
              end a0
              goto bb1
            bb3:
              return
            """))
    }
}

/// A function that stores a new `Hit` in the `var` `h` (`%0`), borrows it at column 3 into the `ref` `r` (`%1`), whose
/// value depends on that borrow, and then runs `statements`, which may use an Int temporary (`%2`), before it returns.
private func borrowingHit(then statements: String) -> (name: String, text: String) {
    let text = """
        func "f()"() -> Void {
          var %0 h: Hit @1:1-1:1
          ref %1 r: Hit @1:1-1:1
          temp %2: Int
        bb0:
          %0 @1:1-1:1 = call "Hit(damage: Int)"(1) @1:1-1:1
          begin a0 read %0 @2:3-2:3
          %1 @1:1-1:1 = operand read %0 @1:1-1:1 @1:1-1:1
          depend %1 on a0
        \(statements)
          return
        }
        """
    return ("f()", text)
}

/// The error for a move of `h.damage` at column 9 while the borrow of `h` at column 3 is live.
private let damageMovedWhileBorrowed = Diagnostic(
    .movedWhileBorrowed(name: "h.damage", borrowed: "h"), at: at(9), labeling: [.init(.borrowed, at: at(3))],
)

/// A function without a body that borrows its first argument and takes its second.
private let pair = (name: "pair(_: &Int, _: Int)", text: #"func "pair(_: &Int, _: Int)"(_: &Int, _: Int) -> Void"#)
