import RayoLLVM
import Testing

@Suite("Running a unary operator on a local's value")
struct UnaryOperationTests {
    @Test func `a checked negation of an Int gives its negative`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 x: Int
              temp %1: Int
            bb0:
              %0 @1:1-1:2 = operand 5 @1:1-1:2
              %1 @1:1-1:2 = negate checked read %0 @1:1-1:2 @1:1-1:2
              \(printInt("%1"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "-5\n"))
    }

    @Test(arguments: [Build.debug, .release])
    func `a wrapping negation of a UInt wraps, in every build`(build: Build) throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 x: UInt
              temp %1: UInt
            bb0:
              %0 @1:1-1:2 = operand UInt 1 @1:1-1:2
              %1 @1:1-1:2 = negate wrapping read %0 @1:1-1:2 @1:1-1:2
              _ = call builtin "print(_: UInt)"(read %1 @1:1-1:2) @1:1-1:2
              return
            }
            """
        #expect(try run(text, in: build) == .init(printed: "18446744073709551615\n"))
    }

    @Test func `a checked negation of a UInt but 0 panics where the build checks overflow`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 x: UInt
              temp %1: UInt
            bb0:
              %0 @1:1-1:2 = operand UInt 1 @1:1-1:2
              %1 @1:1-1:2 = negate checked read %0 @1:1-1:2 @4:9-4:11
              _ = call builtin "print(_: UInt)"(read %1 @1:1-1:2) @1:1-1:2
              return
            }
            """
        #expect(try run(text) == .init(printed: "", panic: "main.rayo:4:9: panic: integer overflow\n"))
    }

    @Test func `not flips a Bool`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 b: Bool
              temp %1: Bool
              temp %2: Bool
            bb0:
              %0 @1:1-1:2 = operand true @1:1-1:2
              %1 @1:1-1:2 = not read %0 @1:1-1:2 @1:1-1:2
              %2 @1:1-1:2 = not read %1 @1:1-1:2 @1:1-1:2
              \(printBool("%1"))
              \(printBool("%2"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "false\ntrue\n"))
    }
}

@Suite("Running a binary operator on locals' values")
struct BinaryOperationTests {
    @Test func `arithmetic computes on its operands' values`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 x: Int
              temp %1: Int
              temp %2: Int
            bb0:
              %0 @1:1-1:2 = operand 7 @1:1-1:2
              %1 @1:1-1:2 = subtract checked read %0 @1:1-1:2, 10 @1:1-1:2
              %2 @1:1-1:2 = multiply checked read %1 @1:1-1:2, read %0 @1:1-1:2 @1:1-1:2
              \(printInt("%1"))
              \(printInt("%2"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "-3\n-21\n"))
    }

    @Test func `a comparison gives a Bool, ordering its operands as their type does`() throws {
        // As Ints, -1 is less than 1; as UInts, the bits of -1 are UInt.max, which is greater.
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 x: Int
              var %1 y: UInt
              temp %2: Bool
              temp %3: Bool
            bb0:
              %0 @1:1-1:2 = operand -1 @1:1-1:2
              %1 @1:1-1:2 = operand UInt 18446744073709551615 @1:1-1:2
              %2 @1:1-1:2 = less read %0 @1:1-1:2, 1 @1:1-1:2
              %3 @1:1-1:2 = less read %1 @1:1-1:2, UInt 1 @1:1-1:2
              \(printBool("%2"))
              \(printBool("%3"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "true\nfalse\n"))
    }

    @Test func `a checked addition that overflows panics at the addition, after what the program printed`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 x: Int
              temp %1: Int
            bb0:
              %0 @1:1-1:2 = operand 9223372036854775807 @1:1-1:2
              \(printInt("%0"))
              %1 @1:1-1:2 = add checked read %0 @1:1-1:2, 1 @6:11-6:16
              \(printInt("%1"))
              return
            }
            """
        let panic = "main.rayo:6:11: panic: integer overflow\n"
        #expect(try run(text) == .init(printed: "9223372036854775807\n", panic: panic))
    }

    @Test func `a checked addition that overflows wraps where the build doesn't check overflow`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 x: Int
              temp %1: Int
            bb0:
              %0 @1:1-1:2 = operand 9223372036854775807 @1:1-1:2
              %1 @1:1-1:2 = add checked read %0 @1:1-1:2, 1 @6:11-6:16
              \(printInt("%1"))
              return
            }
            """
        #expect(try run(text, in: .release) == .init(printed: "-9223372036854775808\n"))
    }

    @Test(arguments: [Build.debug, .release])
    func `a division by zero panics at the division, in every build`(build: Build) throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 zero: Int
              temp %1: Int
            bb0:
              %0 @1:1-1:2 = operand 0 @1:1-1:2
              %1 @1:1-1:2 = divide checked 7, read %0 @1:1-1:2 @2:13-2:18
              \(printInt("%1"))
              return
            }
            """
        #expect(try run(text, in: build) == .init(printed: "", panic: "main.rayo:2:13: panic: division by zero\n"))
    }
}
