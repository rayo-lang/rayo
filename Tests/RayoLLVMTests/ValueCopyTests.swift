import RayoLLVM
import Testing

@Suite("Running an operand that copies a value from one place to another")
struct ValueCopyTests {
    @Test func `a read or a move of a scalar copies its value, and a constant stores itself`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 x: Int
              var %1 y: Int
              var %2 z: Int
              var %3 b: Bool
            bb0:
              %0 @1:1-1:2 = operand 3 @1:1-1:2
              %1 @1:1-1:2 = operand read %0 @1:1-1:2 @1:1-1:2
              %2 @1:1-1:2 = operand move %1 @1:1-1:2 @1:1-1:2
              %3 @1:1-1:2 = operand true @1:1-1:2
              \(printInt("%0"))
              \(printInt("%2"))
              \(printBool("%3"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "3\n3\ntrue\n"))
    }

    @Test func `a copy of a small struct copies each of its fields, and the copy changes apart from it`() throws {
        // `%1` is a copy of `%0`, then `%0` changes, and `%2` takes `%1` by a move.
        let text = programStructs + """
            main "main()"
            func "main()"() -> Void {
              var %0 p: Pair
              var %1 q: Pair
              var %2 r: Pair
            bb0:
              %0 @1:1-1:2 = call "Pair(a: Int, b: Int)"(1, 2) @1:1-1:2
              %1 @1:1-1:2 = operand read %0 @1:1-1:2 @1:1-1:2
              %0.0 @1:1-1:2 = operand 9 @1:1-1:2
              %2 @1:1-1:2 = operand move %1 @1:1-1:2 @1:1-1:2
              \(printInt("%0.0"))
              \(printInt("%2.0"))
              \(printInt("%2.1"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "9\n1\n2\n"))
    }

    @Test func `a copy of a large struct copies each of its fields, and the copy changes apart from it`() throws {
        // `%1` is a copy of `%0`, then `%0` changes, and `%2` takes `%1` by a move.
        let text = programStructs + """
            main "main()"
            func "main()"() -> Void {
              var %0 t: Trio
              var %1 u: Trio
              var %2 v: Trio
            bb0:
              %0 @1:1-1:2 = call "Trio(a: Int, b: Int, c: Bool)"(1, 2, true) @1:1-1:2
              %1 @1:1-1:2 = operand read %0 @1:1-1:2 @1:1-1:2
              %0.1 @1:1-1:2 = operand 9 @1:1-1:2
              %2 @1:1-1:2 = operand move %1 @1:1-1:2 @1:1-1:2
              \(printInt("%0.1"))
              \(printInt("%2.0"))
              \(printInt("%2.1"))
              \(printBool("%2.2"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "9\n1\n2\ntrue\n"))
    }

    @Test func `a copy of a field that holds a struct copies that struct alone`() throws {
        let text = programStructs + """
            main "main()"
            func "main()"() -> Void {
              var %0 box: Box
              var %1 p: Pair
            bb0:
              %0.0 @1:1-1:2 = call "Pair(a: Int, b: Int)"(1, 2) @1:1-1:2
              %1 @1:1-1:2 = operand read %0.0 @1:1-1:2 @1:1-1:2
              \(printInt("%1.0"))
              \(printInt("%1.1"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "1\n2\n"))
    }
}
