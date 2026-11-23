import RayoLLVM
import Testing

@Suite("Running the prelude's print built-ins")
struct PrintTests {
    @Test func `print writes an Int in decimal, a negative one with its sign, and a newline`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
            bb0:
              _ = call builtin "print(_: &Int)"(42) @1:1-1:2
              _ = call builtin "print(_: &Int)"(-9223372036854775808) @1:1-1:2
              return
            }
            """
        #expect(try run(text) == .init(printed: "42\n-9223372036854775808\n"))
    }

    @Test func `print writes a UInt in decimal, the largest one too`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
            bb0:
              _ = call builtin "print(_: &UInt)"(UInt 7) @1:1-1:2
              _ = call builtin "print(_: &UInt)"(UInt 18446744073709551615) @1:1-1:2
              return
            }
            """
        #expect(try run(text) == .init(printed: "7\n18446744073709551615\n"))
    }

    @Test func `print writes a Bool as true or false`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
            bb0:
              _ = call builtin "print(_: &Bool)"(true) @1:1-1:2
              _ = call builtin "print(_: &Bool)"(false) @1:1-1:2
              return
            }
            """
        #expect(try run(text) == .init(printed: "true\nfalse\n"))
    }
}

@Suite("Running the prelude's conversions between its integer types")
struct ConversionTests {
    @Test(arguments: [Build.debug, .release])
    func `a conversion of a value the target type holds keeps the value, in every build`(build: Build) throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 u: UInt @1:1-1:1
              temp %1: Int
              temp %2: UInt
            bb0:
              %0 @1:1-1:2 = operand UInt 7 @1:1-1:2
              %1 @1:1-1:2 = call builtin "Int(_: UInt)"(read %0 @1:1-1:2) @1:1-1:2
              %2 @1:1-1:2 = call builtin "UInt(_: Int)"(read %1 @1:1-1:2) @1:1-1:2
              \(printInt("%1"))
              \(printUInt("%2"))
              return
            }
            """
        #expect(try run(text, in: build) == .init(printed: "7\n7\n"))
    }

    @Test func `a conversion of a value the target type can't hold panics where the build checks overflow`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 x: Int @1:1-1:1
              temp %1: UInt
            bb0:
              %0 @1:1-1:2 = operand -1 @1:1-1:2
              %1 @1:1-1:2 = call builtin "UInt(_: Int)"(read %0 @1:1-1:2) @3:9-3:20
              \(printUInt("%1"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "", panic: "main.rayo:3:9: panic: integer overflow\n"))
    }

    @Test func `a conversion of a value the target can't hold keeps its bits where overflow isn't checked`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 u: UInt @1:1-1:1
              temp %1: Int
            bb0:
              %0 @1:1-1:2 = operand UInt 18446744073709551615 @1:1-1:2
              %1 @1:1-1:2 = call builtin "Int(_: UInt)"(read %0 @1:1-1:2) @3:9-3:20
              \(printInt("%1"))
              return
            }
            """
        #expect(try run(text, in: .release) == .init(printed: "-1\n"))
    }
}
