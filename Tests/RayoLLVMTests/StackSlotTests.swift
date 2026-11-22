import LLVM
@testable import RayoLLVM
import Testing

/// The bytes of an array of a hundred thousand Ints, large enough that how many of them a frame holds is plain from
/// the stack a run uses.
private let largeArrayBytes = 800_000

/// The stack a run may use beside the large arrays it holds: the frames of the code that calls the program, and the
/// small values of its own.
private let smallFrameBytes = 64 * 1024

struct StackSlotTests {
    @Test func `the results of calls that replace one array share one slot, in a release build`() throws {
        // `a` and one result live at once, never more.
        let (run, stackBytes) = try runMeasuringStack(replacingOneArray, in: .release)
        #expect(run == InProcessJIT.Run(printed: "2\n", panic: nil))
        #expect(stackBytes <= 2 * largeArrayBytes + smallFrameBytes)
    }

    @Test func `the copies that calls take as owned arguments share one slot, in a release build`() throws {
        // `a` and one copy live at once, never more.
        let (run, stackBytes) = try runMeasuringStack(passingOwnedCopies, in: .release)
        #expect(run == InProcessJIT.Run(printed: "100001\n100001\n1\n", panic: nil))
        #expect(stackBytes <= 2 * largeArrayBytes + smallFrameBytes)
    }

    @Test func `two call results held in temporaries one after the other share one slot, in a release build`() throws {
        // One array lives at a time, never two.
        let (run, stackBytes) = try runMeasuringStack(summingTwoTemporaries, in: .release)
        #expect(run == InProcessJIT.Run(printed: "100001\n100001\n", panic: nil))
        #expect(stackBytes <= largeArrayBytes + smallFrameBytes)
    }

    @Test func `every slot a function has, but a parameter's, lives only while what it holds is in use`() throws {
        // `p` and `a` lie in slots of their own, from their declarations to their retirements. A struct and an array
        // built from parts of the places they replace are each built in a slot of their own, then copied in, and the
        // loop that fills an array counts in a slot of its own.
        let program = try executable(programStructs + """
            main "main()"
            func "main()"() -> Void {
              var %0 p: Pair @1:1-1:2
              var %1 a: [2 of Int] @1:1-1:2
            bb0:
              declare %0
              %0 @1:1-1:2 = call "Pair(a: Int, b: Int)"(1, 2) @1:1-1:2
              %0 @1:1-1:2 = call "Pair(a: Int, b: Int)"(read %0.1 @1:1-1:2, read %0.0 @1:1-1:2) @1:1-1:2
              retire %0
              declare %1
              %1 @1:1-1:2 = fill 2 of 0 @1:1-1:2
              %1 @1:1-1:2 = array of Int(read %1[1] @1:1-1:2, read %1[0] @1:1-1:2) @1:1-1:2
              retire %1
              return
            }
            """)

        try withEmitted(program) { module in
            let main = try function(named: RuntimeFunction.main.symbol, in: module)
            let allocated = instructions(.allocate, in: main).map { String($0.anyValue.text.split(separator: " ")[0]) }
            #expect(Set(slots(markedBy: "llvm.lifetime.start", in: main)) == Set(allocated))
            #expect(Set(slots(markedBy: "llvm.lifetime.end", in: main)) == Set(allocated))
            #expect(allocated.count == 5)
        }
    }

    /// The names of the slots that calls of the lifetime marker `marker` in `function` take, in the order the calls
    /// come.
    private func slots(markedBy marker: String, in function: Function) -> [String] {
        // Each call is a line of its own, which ends in the slot's name and the call's closing parenthesis.
        let call = "call void @\(marker).p0(ptr "
        let calls = function.text.split(separator: "\n").filter { $0.contains(call) }
        return calls.map { line in String(line.split(separator: call)[1].dropLast()) }
    }
}

/// The IR that `rayoc --emit=ir` gives for this source, which replaces `a` four times a pass with what `bump` returns:
///
/// ```
/// func bump(_ a: [100000 of Int], _ i: UInt) -> [100000 of Int] {
///     var b = copy a
///     b[i] += 1
///     return b
/// }
/// func main() {
///     var a: [100000 of Int] = .init(repeating: 0)
///     var i: UInt = 0
///     while a[1] < 2 {
///         a = bump(a, i)
///         a = bump(a, i + 1)
///         a = bump(a, i + 2)
///         a = bump(a, i + 3)
///         i += 1
///     }
///     print(a[2])
/// }
/// ```
///
/// `bump` reads `a`, so each result goes to a slot of its own before it is copied into `a`. The loop goes on while
/// `a[1]` is under 2, which only running the passes works out, so optimising leaves them in the code. It prints 2.
private let replacingOneArray = """
    main "main()"

    func "bump(_: [100000 of Int], _: UInt)"(_: [100000 of Int], _: UInt) -> [100000 of Int] {
      param %0 a: [100000 of Int] @1:13-1:14
      param %1 i: UInt @1:35-1:36
      var %2 b: [100000 of Int] @2:9-2:10
      temp %3: UInt
    bb0:
      declare %2
      %2 @2:9-2:10 = operand read %0 @2:13-2:19 @2:13-2:19
      declare %3
      %3 @3:7-3:8 = index read %1 @3:7-3:8 below 100000 @3:7-3:8
      %2[%3] @3:5-3:9 = add checked read %2[%3] @3:5-3:9, 1 @3:5-3:9
      retire %3
      return move %2 @4:12-4:13
    bb1:
      unreachable
    }

    func "main()"() -> Void {
      var %0 a: [100000 of Int] @7:9-7:10
      var %1 i: UInt @8:9-8:10
      temp %2: Bool
      temp %3: UInt
      temp %4: UInt
      temp %5: UInt
    bb0:
      declare %0
      %0 @7:9-7:10 = fill 100000 of 0 @7:30-7:49
      declare %1
      %1 @8:9-8:10 = operand UInt 0 @8:19-8:20
      goto bb1
    bb1:
      declare %2
      %2 @9:11-9:19 = less read %0[1] @9:11-9:15, 2 @9:11-9:19
      branch read %2 @9:11-9:19, bb2, bb3
    bb2:
      retire %2
      begin a0 read %0 @10:18-10:19
      begin a1 read %1 @10:21-10:22
      %0 @10:9-10:10 = call "bump(_: [100000 of Int], _: UInt)"(a0, a1) @10:13-10:23
      end a1
      end a0
      declare %3
      %3 @11:21-11:26 = add checked read %1 @11:21-11:22, UInt 1 @11:21-11:26
      begin a2 read %0 @11:18-11:19
      begin a3 read %3 @11:21-11:26
      %0 @11:9-11:10 = call "bump(_: [100000 of Int], _: UInt)"(a2, a3) @11:13-11:27
      end a3
      retire %3
      end a2
      declare %4
      %4 @12:21-12:26 = add checked read %1 @12:21-12:22, UInt 2 @12:21-12:26
      begin a4 read %0 @12:18-12:19
      begin a5 read %4 @12:21-12:26
      %0 @12:9-12:10 = call "bump(_: [100000 of Int], _: UInt)"(a4, a5) @12:13-12:27
      end a5
      retire %4
      end a4
      declare %5
      %5 @13:21-13:26 = add checked read %1 @13:21-13:22, UInt 3 @13:21-13:26
      begin a6 read %0 @13:18-13:19
      begin a7 read %5 @13:21-13:26
      %0 @13:9-13:10 = call "bump(_: [100000 of Int], _: UInt)"(a6, a7) @13:13-13:27
      end a7
      retire %5
      end a6
      %1 @14:9-14:10 = add checked read %1 @14:9-14:10, UInt 1 @14:9-14:10
      goto bb1
    bb3:
      retire %1
      retire %2
      begin a8 read %0[2] @16:11-16:15
      _ = call builtin "print(_: Int)"(a8) @16:5-16:16
      end a8
      retire %0
      return
    }
    """

/// A program that passes a copy of its array `a` to `bumpedSum` twice, which bumps one element of its copy and sums
/// them all, then reads `a` again. Each sum reads the whole copy, so optimising keeps each copy in memory. It prints
/// 100001 twice, then 1. Checking rejects an `owned` parameter that the source writes, so the IR is written here,
/// with each local declared and retired where lowering and the ownership stage would put them.
private let passingOwnedCopies = """
    main "main()"
    func "bumpedSum(_: [100000 of Int], _: UInt)"(_: owned [100000 of Int], _: UInt) -> Int {
      param %0 a: owned [100000 of Int] @1:1-1:2
      param %1 i: UInt @1:1-1:2
      temp %2: UInt
      var %3 sum: Int @1:1-1:2
      var %4 j: UInt @1:1-1:2
      temp %5: Bool
      temp %6: UInt
    bb0:
      declare %2
      %2 @1:1-1:2 = index read %1 @1:1-1:2 below 100000 @1:1-1:2
      %0[%2] @1:1-1:2 = add checked read %0[%2] @1:1-1:2, 1 @1:1-1:2
      retire %2
      declare %3
      %3 @1:1-1:2 = operand 0 @1:1-1:2
      declare %4
      %4 @1:1-1:2 = operand UInt 0 @1:1-1:2
      goto bb1
    bb1:
      declare %5
      %5 @1:1-1:2 = less read %4 @1:1-1:2, UInt 100000 @1:1-1:2
      branch read %5 @1:1-1:2, bb2, bb3
    bb2:
      retire %5
      declare %6
      %6 @1:1-1:2 = index read %4 @1:1-1:2 below 100000 @1:1-1:2
      %3 @1:1-1:2 = add checked read %3 @1:1-1:2, read %0[%6] @1:1-1:2 @1:1-1:2
      retire %6
      %4 @1:1-1:2 = add checked read %4 @1:1-1:2, UInt 1 @1:1-1:2
      goto bb1
    bb3:
      retire %4
      retire %5
      return move %3 @1:1-1:2
    }
    func "main()"() -> Void {
      let %0 a: [100000 of Int] @1:1-1:2
      temp %1: Int
      temp %2: Int
    bb0:
      declare %0
      %0 @1:1-1:2 = fill 100000 of 1 @1:1-1:2
      declare %1
      %1 @1:1-1:2 = call "bumpedSum(_: [100000 of Int], _: UInt)"(read %0 @1:1-1:2, UInt 3) @1:1-1:2
      \(printInt("%1"))
      retire %1
      declare %2
      %2 @1:1-1:2 = call "bumpedSum(_: [100000 of Int], _: UInt)"(read %0 @1:1-1:2, UInt 5) @1:1-1:2
      \(printInt("%2"))
      retire %2
      \(printInt("%0[3]"))
      retire %0
      return
    }
    """

/// The IR that `rayoc --emit=ir` gives for this source, whose two temporaries each hold an array `filled` makes:
///
/// ```
/// func filled(_ i: UInt) -> [100000 of Int] {
///     var a: [100000 of Int] = .init(repeating: 1)
///     a[i] += 1
///     return a
/// }
/// func sum(_ a: [100000 of Int]) -> Int {
///     var total = 0
///     var j: UInt = 0
///     while j < 100000 {
///         total += a[j]
///         j += 1
///     }
///     return total
/// }
/// func main() {
///     print(sum(filled(3)))
///     print(sum(filled(5)))
/// }
/// ```
///
/// Each temporary retires once `sum` has read it, and each sum reads the whole array, so optimising keeps each array
/// in memory. It prints 100001 twice.
private let summingTwoTemporaries = """
    main "main()"

    func "filled(_: UInt)"(_: UInt) -> [100000 of Int] {
      param %0 i: UInt @1:15-1:16
      var %1 a: [100000 of Int] @2:9-2:10
      temp %2: UInt
    bb0:
      declare %1
      %1 @2:9-2:10 = fill 100000 of 1 @2:30-2:49
      declare %2
      %2 @3:7-3:8 = index read %0 @3:7-3:8 below 100000 @3:7-3:8
      %1[%2] @3:5-3:9 = add checked read %1[%2] @3:5-3:9, 1 @3:5-3:9
      retire %2
      return move %1 @4:12-4:13
    bb1:
      unreachable
    }

    func "sum(_: [100000 of Int])"(_: [100000 of Int]) -> Int {
      param %0 a: [100000 of Int] @6:12-6:13
      var %1 total: Int @7:9-7:14
      var %2 j: UInt @8:9-8:10
      temp %3: Bool
      temp %4: UInt
    bb0:
      declare %1
      %1 @7:9-7:14 = operand 0 @7:17-7:18
      declare %2
      %2 @8:9-8:10 = operand UInt 0 @8:19-8:20
      goto bb1
    bb1:
      declare %3
      %3 @9:11-9:21 = less read %2 @9:11-9:12, UInt 100000 @9:11-9:21
      branch read %3 @9:11-9:21, bb2, bb3
    bb2:
      retire %3
      declare %4
      %4 @10:20-10:21 = index read %2 @10:20-10:21 below 100000 @10:20-10:21
      %1 @10:9-10:14 = add checked read %1 @10:9-10:14, read %0[%4] @10:18-10:22 @10:9-10:14
      retire %4
      %2 @11:9-11:10 = add checked read %2 @11:9-11:10, UInt 1 @11:9-11:10
      goto bb1
    bb3:
      retire %2
      retire %3
      return move %1 @13:12-13:17
    bb4:
      unreachable
    }

    func "main()"() -> Void {
      temp %0: Int
      temp %1: [100000 of Int]
      temp %2: Int
      temp %3: [100000 of Int]
    bb0:
      declare %0
      declare %1
      %1 @16:15-16:24 = call "filled(_: UInt)"(UInt 3) @16:15-16:24
      begin a0 read %1 @16:15-16:24
      %0 @16:11-16:25 = call "sum(_: [100000 of Int])"(a0) @16:11-16:25
      end a0
      retire %1
      begin a1 read %0 @16:11-16:25
      _ = call builtin "print(_: Int)"(a1) @16:5-16:26
      end a1
      retire %0
      declare %2
      declare %3
      %3 @17:15-17:24 = call "filled(_: UInt)"(UInt 5) @17:15-17:24
      begin a2 read %3 @17:15-17:24
      %2 @17:11-17:25 = call "sum(_: [100000 of Int])"(a2) @17:11-17:25
      end a2
      retire %3
      begin a3 read %2 @17:11-17:25
      _ = call builtin "print(_: Int)"(a3) @17:5-17:26
      end a3
      retire %2
      return
    }
    """
