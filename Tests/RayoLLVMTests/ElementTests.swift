import RayoLLVM
import Testing

@Suite("Running reads and stores of an array's elements")
struct ElementTests {
    @Test(arguments: [Build.debug, .release])
    func `an index outside the array panics at the index, in every build`(build: Build) throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 a: [3 of Int] @1:1-1:1
              var %1 i: UInt @1:1-1:1
              temp %2: UInt
            bb0:
              %0 @1:1-1:2 = array of Int(1, 2, 3) @1:1-1:2
              %1 @1:1-1:2 = operand UInt 3 @1:1-1:2
              _ = call builtin "print(_: &Int)"(1) @1:1-1:2
              %2 @1:1-1:2 = index read %1 @1:1-1:2 below 3 @5:19-5:20
              begin a0 read %0[%2] @1:1-1:2
              _ = call builtin "print(_: &Int)"(a0) @1:1-1:2
              end a0
              return
            }
            """
        #expect(try run(text, in: build) == .init(printed: "1\n", panic: "main.rayo:5:19: panic: index out of range\n"))
    }

    @Test(arguments: [Build.debug, .release])
    func `an index inside the array reads and writes the element at it, in every build`(build: Build) throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 a: [3 of Int] @1:1-1:1
              var %1 i: UInt @1:1-1:1
              temp %2: UInt
            bb0:
              %0 @1:1-1:2 = array of Int(1, 2, 3) @1:1-1:2
              %1 @1:1-1:2 = operand UInt 2 @1:1-1:2
              %2 @1:1-1:2 = index read %1 @1:1-1:2 below 3 @1:1-1:2
              \(printInt("%0[%2]", through: 0))
              %0[%2] @1:1-1:2 = operand 9 @1:1-1:2
              \(printInt("%0[2]", through: 1))
              return
            }
            """
        #expect(try run(text, in: build) == .init(printed: "3\n9\n"))
    }

    @Test(arguments: [Build.debug, .release])
    func `an array read whole after one of its elements changes holds the new element beside the others`(
        build: Build,
    ) throws {
        // The element at index 1 changes twice, the second time in place, then the array is passed whole to `total`
        // and moved whole into another local.
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 a: [2 of Int] @1:1-1:1
              var %1 b: [2 of Int] @1:1-1:1
              temp %2: UInt
              temp %3: Int
            bb0:
              %0 @1:1-1:2 = array of Int(1, 2) @1:1-1:2
              %2 @1:1-1:2 = index UInt 1 below 2 @1:1-1:2
              %0[%2] @1:1-1:2 = operand 7 @1:1-1:2
              %0[%2] @1:1-1:2 = add checked read %0[%2] @1:1-1:2, 10 @1:1-1:2
              begin a0 read %0 @1:1-1:2
              %3 @1:1-1:2 = call "total(_: [2 of Int])"(a0) @1:1-1:2
              end a0
              \(printInt("%3", through: 1))
              %1 @1:1-1:2 = operand move %0 @1:1-1:2 @1:1-1:2
              \(printInt("%1[0]", through: 2))
              \(printInt("%1[1]", through: 3))
              return
            }
            func "total(_: [2 of Int])"(_: &[2 of Int]) -> Int {
              param %0 a: &[2 of Int] @1:1-1:1
              temp %1: Int
            bb0:
              %1 @1:1-1:2 = add checked read %0[0] @1:1-1:2, read %0[1] @1:1-1:2 @1:1-1:2
              return read %1 @1:1-1:2
            }
            """
        #expect(try run(text, in: build) == .init(printed: "18\n1\n17\n"))
    }

    @Test(arguments: [Build.debug, .release])
    func `an index outside the array panics before the element it would reach is written`(build: Build) throws {
        // The index is checked in the statement before the store whose place leads through it, so the panic comes
        // before the store, and before the print after it.
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 a: [3 of Int] @1:1-1:1
              var %1 i: UInt @1:1-1:1
              temp %2: UInt
            bb0:
              %0 @1:1-1:2 = array of Int(1, 2, 3) @1:1-1:2
              %1 @1:1-1:2 = operand UInt 3 @1:1-1:2
              %2 @1:1-1:2 = index read %1 @1:1-1:2 below 3 @4:5-4:6
              %0[%2] @1:1-1:2 = operand 9 @1:1-1:2
              \(printInt("%0[0]", through: 0))
              return
            }
            """
        #expect(try run(text, in: build) == .init(printed: "", panic: "main.rayo:4:5: panic: index out of range\n"))
    }
}
