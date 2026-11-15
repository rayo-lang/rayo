import RayoLLVM
import Testing

@Suite("Running an array literal")
struct ArrayLiteralTests {
    @Test func `an array of scalars holds its elements in order`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 a: [3 of Int]
              var %1 b: [2 of Bool]
            bb0:
              %0 @1:1-1:2 = array of Int(4, 5, 6) @1:1-1:2
              %1 @1:1-1:2 = array of Bool(false, true) @1:1-1:2
              \(printInt("%0[0]"))
              \(printInt("%0[1]"))
              \(printInt("%0[2]"))
              \(printBool("%1[0]"))
              \(printBool("%1[1]"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "4\n5\n6\nfalse\ntrue\n"))
    }

    @Test func `an array of structs holds a copy of each`() throws {
        let text = programStructs + """
            main "main()"
            func "main()"() -> Void {
              var %0 p: Pair
              var %1 t: Trio
              var %2 pairs: [2 of Pair]
              var %3 trios: [2 of Trio]
            bb0:
              %0 @1:1-1:2 = call "Pair(a: Int, b: Int)"(1, 2) @1:1-1:2
              %1 @1:1-1:2 = call "Trio(a: Int, b: Int, c: Bool)"(3, 4, true) @1:1-1:2
              %2 @1:1-1:2 = array of Pair(read %0 @1:1-1:2, read %0 @1:1-1:2) @1:1-1:2
              %3 @1:1-1:2 = array of Trio(read %1 @1:1-1:2, move %1 @1:1-1:2) @1:1-1:2
              %2[0].0 @1:1-1:2 = operand 9 @1:1-1:2
              \(printInt("%2[0].0"))
              \(printInt("%2[1].0"))
              \(printInt("%2[1].1"))
              \(printInt("%3[1].1"))
              \(printBool("%3[1].2"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "9\n1\n2\n4\ntrue\n"))
    }

    @Test func `an array of arrays holds each inner array whole`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 row: [2 of Int]
              var %1 grid: [2 of [2 of Int]]
            bb0:
              %0 @1:1-1:2 = array of Int(1, 2) @1:1-1:2
              %1 @1:1-1:2 = array of [2 of Int](read %0 @1:1-1:2, read %0 @1:1-1:2) @1:1-1:2
              %1[1][0] @1:1-1:2 = operand 3 @1:1-1:2
              \(printInt("%1[0][0]"))
              \(printInt("%1[0][1]"))
              \(printInt("%1[1][0]"))
              \(printInt("%1[1][1]"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "1\n2\n3\n2\n"))
    }

    @Test func `an empty array stores nothing, and the program goes on`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 a: [0 of Int]
            bb0:
              %0 @1:1-1:2 = array of Int() @1:1-1:2
              _ = call builtin "print(_: Int)"(1) @1:1-1:2
              return
            }
            """
        #expect(try run(text) == .init(printed: "1\n"))
    }

    @Test(arguments: [Build.debug, .release])
    func `an array whose elements read the array itself is built from the elements as they were`(build: Build) throws {
        // The array swaps its first two elements, so one built in place would read an element it had just written.
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 a: [3 of Int]
            bb0:
              %0 @1:1-1:2 = array of Int(1, 2, 3) @1:1-1:2
              %0 @1:1-1:2 = array of Int(read %0[1] @1:1-1:2, read %0[0] @1:1-1:2, 9) @1:1-1:2
              \(printInt("%0[0]"))
              \(printInt("%0[1]"))
              \(printInt("%0[2]"))
              return
            }
            """
        #expect(try run(text, in: build) == .init(printed: "2\n1\n9\n"))
    }
}

@Suite("Running an array filled with copies of one value")
struct FilledArrayTests {
    @Test func `a filled array holds the value in each element, and a change to one leaves the others`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 a: [3 of Int]
            bb0:
              %0 @1:1-1:2 = fill 3 of 7 @1:1-1:2
              %0[1] @1:1-1:2 = operand 8 @1:1-1:2
              \(printInt("%0[0]"))
              \(printInt("%0[1]"))
              \(printInt("%0[2]"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "7\n8\n7\n"))
    }

    @Test func `an array filled with a struct holds a copy of it in each element`() throws {
        let text = programStructs + """
            main "main()"
            func "main()"() -> Void {
              var %0 t: Trio
              var %1 trios: [2 of Trio]
            bb0:
              %0 @1:1-1:2 = call "Trio(a: Int, b: Int, c: Bool)"(1, 2, true) @1:1-1:2
              %1 @1:1-1:2 = fill 2 of read %0 @1:1-1:2 @1:1-1:2
              %1[0].1 @1:1-1:2 = operand 5 @1:1-1:2
              \(printInt("%1[0].1"))
              \(printInt("%1[1].0"))
              \(printInt("%1[1].1"))
              \(printBool("%1[1].2"))
              \(printInt("%0.1"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "5\n1\n2\ntrue\n2\n"))
    }

    @Test func `an array filled with no copies stores nothing, and the program goes on`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 a: [0 of Int]
            bb0:
              %0 @1:1-1:2 = fill 0 of 7 @1:1-1:2
              _ = call builtin "print(_: Int)"(1) @1:1-1:2
              return
            }
            """
        #expect(try run(text) == .init(printed: "1\n"))
    }
}
