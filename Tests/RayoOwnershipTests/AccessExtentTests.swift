import RayoDiagnostics
import RayoIR
import RayoOwnership
import RayoSema
import Testing

@Suite("Where accesses end, and which of them conflict")
struct AccessExtentTests {
    @Test func `a modify access and a read access of one place, live across one call, conflict`() throws {
        // As `g(&x, x)` lowers: the modify access is still live where the read access begins.
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 modify static %0 @2:3-2:3
              begin a1 read static %0 @2:6-2:6
              _ = call "g(_: Int, _: Int)"(a0, a1) @1:1-1:1
              return
            """
        let expected = Diagnostic(
            .usedWhileMutablyBorrowed(name: "x", borrowed: "x"), at: at(6), labeling: [.init(.borrowed, at: at(3))],
        )
        #expect(try checked(blocks).errors == [expected])
    }

    @Test func `accesses to two fields of one value don't conflict, whatever they do`() throws {
        // As `take(&s.range, s.hit)` lowers.
        let blocks = """
            bb0:
            \(storeShot())
              begin a0 modify static %5.0 @2:3-2:3
              begin a1 read static %5.1 @2:6-2:6
              _ = call "take(_: Int, _: Hit)"(a0, a1) @1:1-1:1
              return
            """
        #expect(try checked(blocks).errors == [])
    }

    @Test func `two read accesses of one place don't conflict`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read static %0 @2:3-2:3
              begin a1 read static %0 @2:6-2:6
              _ = call "g(_: Int, _: Int)"(a0, a1) @1:1-1:1
              return
            """
        #expect(try checked(blocks).errors == [])
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
              begin a0 read static %5.1 @2:3-2:3
              \(change)
              _ = call "take(_: Int, _: Hit)"(1, a0) @1:1-1:1
              return
            """
        #expect(try checked(blocks).errors == [Diagnostic(code, at: at(6), labeling: [.init(.borrowed, at: at(3))])])
    }

    @Test func `a read of a place that a live modify access overlaps conflicts with it`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 modify static %0 @2:3-2:3
              %1 @1:1-1:1 = operand read %0 @2:6-2:6 @1:1-1:1
              _ = call "g(_: Int, _: Int)"(a0, 1) @1:1-1:1
              return
            """
        let expected = Diagnostic(
            .usedWhileMutablyBorrowed(name: "x", borrowed: "x"), at: at(6), labeling: [.init(.borrowed, at: at(3))],
        )
        #expect(try checked(blocks).errors == [expected])
    }

    @Test func `a change after an access's last use, or a store of what its call gives, conflicts with none`() throws {
        // As `x = double(x)` lowers, then a change to `x` once nothing uses the access.
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read static %0 @2:3-2:3
              %0 @2:5-2:5 = call "double(_: Int)"(a0) @1:1-1:1
              %0 @2:6-2:6 = operand 2 @1:1-1:1
              _ = call "g(_: Int, _: Int)"(1, 2) @1:1-1:1
              return
            """
        #expect(try checked(blocks).errors == [])
    }

    @Test func `an access ends after its last use, the latest begun first`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read static %0 @1:1-1:1
              begin a1 read static %0 @1:1-1:1
              _ = call "g(_: Int, _: Int)"(a0, a1) @1:1-1:1
              _ = call "g(_: Int, _: Int)"(1, 2) @1:1-1:1
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read static %0 @1:1-1:1
              begin a1 read static %0 @1:1-1:1
              _ = call "g(_: Int, _: Int)"(a0, a1) @1:1-1:1
              end a1
              end a0
              _ = call "g(_: Int, _: Int)"(1, 2) @1:1-1:1
              return
            """))
    }

    @Test func `an access that nothing uses ends where it begins`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read static %0 @1:1-1:1
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read static %0 @1:1-1:1
              end a0
              return
            """))
    }

    @Test func `an access live into one branch only ends there after its use, and as the other branch starts`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read static %0 @1:1-1:1
              branch read %6 @1:1-1:1, bb1, bb2
            bb1:
              _ = call "g(_: Int, _: Int)"(a0, 1) @1:1-1:1
              goto bb3
            bb2:
              goto bb3
            bb3:
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read static %0 @1:1-1:1
              branch read %6 @1:1-1:1, bb1, bb2
            bb1:
              _ = call "g(_: Int, _: Int)"(a0, 1) @1:1-1:1
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
              begin a0 read static %0 @1:1-1:1
              branch read %6 @1:1-1:1, bb1, bb2
            bb1:
              _ = call "g(_: Int, _: Int)"(a0, 1) @1:1-1:1
              goto bb2
            bb2:
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read static %0 @1:1-1:1
              branch read %6 @1:1-1:1, bb1, bb3
            bb1:
              _ = call "g(_: Int, _: Int)"(a0, 1) @1:1-1:1
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
              begin a0 read static %0 @1:1-1:1
              branch read %6 @1:1-1:1, bb0, bb2
            bb2:
              _ = call "g(_: Int, _: Int)"(a0, 1) @1:1-1:1
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb1
            bb1:
              begin a0 read static %0 @1:1-1:1
              branch read %6 @1:1-1:1, bb3, bb2
            bb2:
              _ = call "g(_: Int, _: Int)"(a0, 1) @1:1-1:1
              end a0
              return
            bb3:
              end a0
              goto bb0
            """))
    }

    @Test func `an access ends only on paths that began it, though a value that may depend on it is used on`() throws {
        // `y` may depend on the access where the paths join, but the path through `bb2` never began it.
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              branch read %6 @1:1-1:1, bb1, bb2
            bb1:
              begin a0 read static %0 @1:1-1:1
              %1 @1:1-1:1 = operand 2 @1:1-1:1
              depend %1 on a0
              goto bb3
            bb2:
              %1 @1:1-1:1 = operand 3 @1:1-1:1
              goto bb3
            bb3:
              %3 @1:1-1:1 = operand read %1 @1:1-1:1 @1:1-1:1
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              branch read %6 @1:1-1:1, bb1, bb2
            bb1:
              begin a0 read static %0 @1:1-1:1
              %1 @1:1-1:1 = operand 2 @1:1-1:1
              depend %1 on a0
              goto bb4
            bb2:
              %1 @1:1-1:1 = operand 3 @1:1-1:1
              goto bb3
            bb3:
              %3 @1:1-1:1 = operand read %1 @1:1-1:1 @1:1-1:1
              return
            bb4:
              end a0
              goto bb3
            """))
    }

    @Test func `after paths join, a change conflicts with an access one began that a value may depend on`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              branch read %6 @1:1-1:1, bb1, bb2
            bb1:
              begin a0 read static %0 @2:3-2:3
              %1 @1:1-1:1 = operand 2 @1:1-1:1
              depend %1 on a0
              goto bb3
            bb2:
              %1 @1:1-1:1 = operand 3 @1:1-1:1
              goto bb3
            bb3:
              %0 @2:6-2:6 = operand 4 @1:1-1:1
              %3 @1:1-1:1 = operand read %1 @1:1-1:1 @1:1-1:1
              return
            """
        let expected = Diagnostic(
            .changedWhileBorrowed(name: "x", borrowed: "x"), at: at(6), labeling: [.init(.borrowed, at: at(3))],
        )
        #expect(try checked(blocks).errors == [expected])
    }

    @Test func `an access begun in a loop's body ends in the body, on each pass`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb1
            bb1:
              branch read %6 @1:1-1:1, bb2, bb3
            bb2:
              begin a0 read static %0 @1:1-1:1
              _ = call "g(_: Int, _: Int)"(a0, 1) @1:1-1:1
              goto bb1
            bb3:
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              goto bb1
            bb1:
              branch read %6 @1:1-1:1, bb2, bb3
            bb2:
              begin a0 read static %0 @1:1-1:1
              _ = call "g(_: Int, _: Int)"(a0, 1) @1:1-1:1
              end a0
              goto bb1
            bb3:
              return
            """))
    }

    @Test func `an access a value depends on stays live through the last use of the value and its copies`() throws {
        // `y` depends on the access, and `k` on it through a copy of `y`, so the access ends after `k`'s last use.
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              %1 @1:1-1:1 = operand 2 @1:1-1:1
              begin a0 read static %0 @2:3-2:3
              depend %1 on a0
              %2 @1:1-1:1 = operand read %1 @1:1-1:1 @1:1-1:1
              _ = call "g(_: Int, _: Int)"(1, 2) @1:1-1:1
              %3 @1:1-1:1 = operand read %2 @1:1-1:1 @1:1-1:1
              _ = call "g(_: Int, _: Int)"(1, 2) @1:1-1:1
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              %1 @1:1-1:1 = operand 2 @1:1-1:1
              begin a0 read static %0 @2:3-2:3
              depend %1 on a0
              %2 @1:1-1:1 = operand read %1 @1:1-1:1 @1:1-1:1
              _ = call "g(_: Int, _: Int)"(1, 2) @1:1-1:1
              %3 @1:1-1:1 = operand read %2 @1:1-1:1 @1:1-1:1
              end a0
              _ = call "g(_: Int, _: Int)"(1, 2) @1:1-1:1
              return
            """))
    }

    @Test func `a change to the place of an access a value depends on conflicts until the value's last use`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              %1 @1:1-1:1 = operand 2 @1:1-1:1
              begin a0 read static %0 @2:3-2:3
              depend %1 on a0
              %0 @2:6-2:6 = operand 3 @1:1-1:1
              %3 @1:1-1:1 = operand read %1 @1:1-1:1 @1:1-1:1
              %0 @2:9-2:9 = operand 4 @1:1-1:1
              return
            """
        let expected = Diagnostic(
            .changedWhileBorrowed(name: "x", borrowed: "x"), at: at(6), labeling: [.init(.borrowed, at: at(3))],
        )
        #expect(try checked(blocks).errors == [expected])
    }

    @Test func `a value assigned anew no longer depends on the access, which then ends`() throws {
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              %1 @1:1-1:1 = operand 2 @1:1-1:1
              begin a0 read static %0 @1:1-1:1
              depend %1 on a0
              %1 @1:1-1:1 = operand 5 @1:1-1:1
              %3 @1:1-1:1 = operand read %1 @1:1-1:1 @1:1-1:1
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              %1 @1:1-1:1 = operand 2 @1:1-1:1
              begin a0 read static %0 @1:1-1:1
              depend %1 on a0
              end a0
              %1 @1:1-1:1 = operand 5 @1:1-1:1
              %3 @1:1-1:1 = operand read %1 @1:1-1:1 @1:1-1:1
              return
            """))
    }
}

/// The functions that `main`'s blocks call, which have no bodies.
private let callees = [
    (name: "g(_: Int, _: Int)", text: #"func "g(_: Int, _: Int)"(Int, Int) -> Void"#),
    (name: "take(_: Int, _: Hit)", text: #"func "take(_: Int, _: Hit)"(Int, Hit) -> Void"#),
    (name: "double(_: Int)", text: #"func "double(_: Int)"(Int) -> Int"#),
]

/// What the check makes of a `main` of `blocks`, with the locals `function` gives it.
private func checked(_ blocks: String) throws -> (program: IRProgram, errors: [Diagnostic]) {
    let (program, errors) = ExclusivityChecker.check(try program(of: [function(blocks, named: "main()")] + callees))
    return (program, errors[FunctionID(index: 0)] ?? [])
}

/// The body of a `main` of `blocks` once the check has written the ends of its accesses into it.
private func ended(_ blocks: String) throws -> IRBody? {
    try checked(blocks).program.bodies[FunctionID(index: 0)]
}

/// The body of a `main` of `blocks`, as the text writes it.
private func body(of blocks: String) throws -> IRBody? {
    try program(of: [function(blocks, named: "main()")] + callees).bodies[FunctionID(index: 0)]
}
