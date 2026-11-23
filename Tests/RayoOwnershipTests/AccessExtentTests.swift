@testable import RayoOwnership
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

    @Test func `merges over eight times as many loops read under twenty-eight times as much`() throws {
        let short = try mergeReads(solving: loopingFunction(loops: 50))
        let long = try mergeReads(solving: loopingFunction(loops: 400))

        // Merges read about twelve times as much: eight times as many, each a little wider as the arrays' nodes fill.
        // States that hold an entry for every access read about sixty-three times as much.
        #expect(long < short * 28)
    }
}

/// How much of the dependence and unbegun-access states the solver's merges read, solving them through `function`.
private func mergeReads(solving function: (name: String, text: String)) throws -> Int {
    let program = try program(of: [function] + callees, from: .lowering)
    let body = try #require(program.bodies[FunctionID(index: 0)])
    let (dependencies, unbegun) = AccessExtents.entryStates(of: body)

    let reads = ReadCount()
    _ = DataflowSolver.solve(from: CountingReads(dependencies, into: reads), through: body, knowing: ())
    _ = DataflowSolver.solve(from: CountingReads(unbegun, into: reads), through: body, knowing: ())
    return reads.count
}

/// A count of what merges read; a class, since every copy of a state adds to one count.
private final class ReadCount {
    var count = 0
}

/// A state that says how much of its storage another state doesn't share, which a merge of the two reads.
private protocol SharingState: DataflowState where Function == Void {
    func unsharedSlots(comparedWith other: Self) -> Int
}

extension DependencyState: SharingState {}
extension UnbegunAccessState: SharingState {}

/// A state that carries `inner`, and adds to `reads` how much of the two states each merge reads.
private struct CountingReads<Inner: SharingState>: DataflowState {
    var inner: Inner
    let reads: ReadCount

    init(_ inner: Inner, into reads: ReadCount) {
        self.inner = inner
        self.reads = reads
    }

    var direction: DataflowDirection { inner.direction }

    func merged(with other: CountingReads) -> CountingReads {
        reads.count += inner.unsharedSlots(comparedWith: other.inner)
        return CountingReads(inner.merged(with: other.inner), into: reads)
    }

    mutating func apply(_ effect: Effect, in function: Void) {
        inner.apply(effect, in: ())
    }

    static func == (first: CountingReads, second: CountingReads) -> Bool {
        first.inner == second.inner
    }
}
