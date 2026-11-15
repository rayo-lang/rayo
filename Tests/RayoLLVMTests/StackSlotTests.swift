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
        // As the source lowers that replaces `a` four times a pass with what `bump` returns, which reads `a`, so each
        // result goes to a slot of its own before it is copied into `a`. The loop goes on while `a[1]` is under 2,
        // which only running the passes works out, so optimising leaves them in the code.
        let calls = (0..<4).map { offset in
            """
              %\(offset + 3) @1:1-1:2 = add checked read %1 @1:1-1:2, UInt \(offset) @1:1-1:2
              begin a\(2 * offset) read static %0 @1:1-1:2
              begin a\(2 * offset + 1) read static %\(offset + 3) @1:1-1:2
              %0 @1:1-1:2 = call "bump(_: [100000 of Int], _: UInt)"(a\(2 * offset), a\(2 * offset + 1)) @1:1-1:2
              end a\(2 * offset + 1)
              end a\(2 * offset)
            """
        }
        let program = """
            main "main()"
            func "bump(_: [100000 of Int], _: UInt)"(_: [100000 of Int], _: UInt) -> [100000 of Int] {
              param %0 a: [100000 of Int] @1:1-1:2
              param %1 i: UInt @1:1-1:2
              var %2 b: [100000 of Int] @1:1-1:2
              temp %3: UInt
            bb0:
              declare %2
              %2 @1:1-1:2 = operand read %0 @1:1-1:2 @1:1-1:2
              %3 @1:1-1:2 = index read %1 @1:1-1:2 below 100000 @1:1-1:2
              %2[%3] @1:1-1:2 = add checked read %2[%3] @1:1-1:2, 1 @1:1-1:2
              return move %2 @1:1-1:2
            }
            func "main()"() -> Void {
              var %0 a: [100000 of Int] @1:1-1:2
              var %1 i: UInt @1:1-1:2
              temp %2: Bool
              temp %3: UInt
              temp %4: UInt
              temp %5: UInt
              temp %6: UInt
            bb0:
              declare %0
              %0 @1:1-1:2 = fill 100000 of 0 @1:1-1:2
              declare %1
              %1 @1:1-1:2 = operand UInt 0 @1:1-1:2
              goto bb1
            bb1:
              %2 @1:1-1:2 = less read %0[1] @1:1-1:2, 2 @1:1-1:2
              branch read %2 @1:1-1:2, bb2, bb3
            bb2:
            \(calls.joined(separator: "\n"))
              %1 @1:1-1:2 = add checked read %1 @1:1-1:2, UInt 1 @1:1-1:2
              goto bb1
            bb3:
              begin a8 read static %0[2] @1:1-1:2
              _ = call builtin "print(_: Int)"(a8) @1:1-1:2
              end a8
              return
            }
            """

        // `a` and one result live at once, never more.
        let (run, stackBytes) = try runMeasuringStack(program, in: .release)
        #expect(run == InProcessJIT.Run(printed: "2\n", panic: nil))
        #expect(stackBytes <= 2 * largeArrayBytes + smallFrameBytes)
    }

    @Test func `the copies that calls take as owned arguments share one slot, in a release build`() throws {
        // `main` passes a copy of `a` to `bumpedSum` twice, which bumps one element of its copy and sums them all.
        // Each sum reads the whole copy, so optimising keeps each copy in memory.
        let program = """
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
              declare %3
              %3 @1:1-1:2 = operand 0 @1:1-1:2
              declare %4
              %4 @1:1-1:2 = operand UInt 0 @1:1-1:2
              goto bb1
            bb1:
              %5 @1:1-1:2 = less read %4 @1:1-1:2, UInt 100000 @1:1-1:2
              branch read %5 @1:1-1:2, bb2, bb3
            bb2:
              %6 @1:1-1:2 = index read %4 @1:1-1:2 below 100000 @1:1-1:2
              %3 @1:1-1:2 = add checked read %3 @1:1-1:2, read %0[%6] @1:1-1:2 @1:1-1:2
              %4 @1:1-1:2 = add checked read %4 @1:1-1:2, UInt 1 @1:1-1:2
              goto bb1
            bb3:
              return read %3 @1:1-1:2
            }
            func "main()"() -> Void {
              var %0 a: [100000 of Int] @1:1-1:2
              temp %1: Int
              temp %2: Int
            bb0:
              declare %0
              %0 @1:1-1:2 = fill 100000 of 1 @1:1-1:2
              %1 @1:1-1:2 = call "bumpedSum(_: [100000 of Int], _: UInt)"(read %0 @1:1-1:2, UInt 3) @1:1-1:2
              %2 @1:1-1:2 = call "bumpedSum(_: [100000 of Int], _: UInt)"(read %0 @1:1-1:2, UInt 5) @1:1-1:2
              _ = call builtin "print(_: Int)"(read %1 @1:1-1:2) @1:1-1:2
              _ = call builtin "print(_: Int)"(read %2 @1:1-1:2) @1:1-1:2
              _ = call builtin "print(_: Int)"(read %0[3] @1:1-1:2) @1:1-1:2
              return
            }
            """

        // `a` and one copy live at once, never more.
        let (run, stackBytes) = try runMeasuringStack(program, in: .release)
        #expect(run == InProcessJIT.Run(printed: "100001\n100001\n1\n", panic: nil))
        #expect(stackBytes <= 2 * largeArrayBytes + smallFrameBytes)
    }

    @Test func `a slot that one operation builds a value in lives only while the operation uses it`() throws {
        // A struct and an array built from parts of the places they replace are each built in a slot of their own,
        // then copied in, and the loop that fills an array counts in a slot of its own.
        let program = try executable(programStructs + """
            main "main()"
            func "main()"() -> Void {
              var %0 p: Pair @1:1-1:2
              var %1 a: [2 of Int] @1:1-1:2
            bb0:
              declare %0
              %0 @1:1-1:2 = call "Pair(a: Int, b: Int)"(1, 2) @1:1-1:2
              %0 @1:1-1:2 = call "Pair(a: Int, b: Int)"(read %0.1 @1:1-1:2, read %0.0 @1:1-1:2) @1:1-1:2
              declare %1
              %1 @1:1-1:2 = fill 2 of 0 @1:1-1:2
              %1 @1:1-1:2 = array of Int(read %1[1] @1:1-1:2, read %1[0] @1:1-1:2) @1:1-1:2
              return
            }
            """)

        try withEmitted(program) { module in
            let main = try function(named: RuntimeFunction.main.symbol, in: module)
            let started = slots(markedBy: "llvm.lifetime.start", in: main)
            #expect(started.count == 3)
            #expect(Set(started) == Set(slots(markedBy: "llvm.lifetime.end", in: main)))
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
