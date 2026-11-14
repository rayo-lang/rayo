import RayoIR
import RayoSema
import RayoSource
import Testing

/// Text that isn't Rayo IR, and the error the parser reports for it.
struct MalformedIR: CustomTestStringConvertible, Sendable {
    let testDescription: String
    let text: String
    let error: IRTextError
}

@Suite("Reading Rayo IR's text")
struct IRTextTests {
    @Test(arguments: malformedIR)
    func `text that isn't Rayo IR is reported at the line and column the parser stops at`(ir: MalformedIR) {
        #expect(throws: ir.error) { try IRParser.program(from: ir.text) }
    }

    @Test func `comments are skipped, and a function's parts may be laid out across lines in any way`() throws {
        let program = try IRParser.program(from: """
            // The program's one function.
            main "main()" func "main()"(
            ) -> Void { temp %0: Int bb0: %0 @1:1-1:2 = operand -9223372036854775808 @1:1-1:2 return }
            """)
        #expect(IRPrinter.text(of: program) == """
            main "main()"

            func "main()"() -> Void {
              temp %0: Int
            bb0:
              %0 @1:1-1:2 = operand -9223372036854775808 @1:1-1:2
              return
            }

            """)
    }

    @Test func `a UInt local, a UInt constant and a conversion read back the same`() throws {
        let text = """
            main "main()"

            func "main()"() -> Void {
              var %0 x: UInt
              temp %1: Int
            bb0:
              %0 @1:1-1:2 = operand uint 18446744073709551615 @1:1-1:2
              begin a0 read static %0 @2:3-2:4
              %1 @2:1-2:2 = call builtin "Int(_: UInt)"(a0) @2:1-2:2
              end a0
              return
            }

            """
        let program = try IRParser.program(from: text)
        #expect(IRPrinter.text(of: program) == text)
    }

    @Test func `an access begun, passed to a call, depended on and ended reads back the same`() throws {
        let text = """
            main "main()"

            func "main()"() -> Void {
              var %0 x: Int
              temp %1: Int
            bb0:
              %0 @1:1-1:2 = operand 1 @1:1-1:2
              begin a0 read static %0 @2:3-2:4
              begin a1 modify dynamic %0 @2:6-2:7
              _ = call builtin "print(_: Int)"(a0, 2) @1:1-1:2
              %1 @1:1-1:2 = operand 3 @1:1-1:2
              depend %1 on a1
              end a1
              end a0
              return
            }

            """
        let program = try IRParser.program(from: text)
        #expect(IRPrinter.text(of: program) == text)

        // The statements hold the accesses as they are written.
        let statements = try #require(program.bodies[FunctionID(index: 0)]).blocks[0].statements
        let access = Access(.read, .static, to: Place(root: LocalID(index: 0)), at: range(2, 3, 2, 4))
        #expect(statements[1] == .begin(AccessID(index: 0), access))
        let arguments: [CallArgument] = [.access(AccessID(index: 0)), .operand(.constant(.int(2)))]
        #expect(statements[3] == .compute(
            destination: nil, value: .call(.builtin(.printInt), arguments: arguments), range: range(1, 1, 1, 2),
        ))
        #expect(statements[5] == .depend(Place(root: LocalID(index: 1)), on: AccessID(index: 1)))
        #expect(statements[6] == .end(AccessID(index: 1)))
    }

    @Test func `array types, and an array made of its elements, read back the same`() throws {
        let text = """
            struct Grid {
              rows: [2 of [3 of Bool]]
            }

            main "main()"

            func "main()"() -> Void {
              var %0 a: [2 of Int]
              temp %1: [0 of Grid]
            bb0:
              %0 @1:1-1:2 = array of Int(1, move %0 @2:3-2:4) @1:1-1:2
              %1 @1:1-1:2 = array of Grid() @1:1-1:2
              return
            }

            """
        let program = try IRParser.program(from: text)
        #expect(IRPrinter.text(of: program) == text)

        // The array names its element type, and holds its elements in order.
        let statements = try #require(program.bodies[FunctionID(index: 0)]).blocks[0].statements
        let elements: [Operand] = [.constant(.int(1)), .move(Place(root: LocalID(index: 0)), at: range(2, 3, 2, 4))]
        #expect(statements[0] == .compute(
            destination: Destination(Place(root: LocalID(index: 0)), at: range(1, 1, 1, 2)),
            value: .array(elements, of: .int), range: range(1, 1, 1, 2),
        ))
    }
}

/// The range the text writes `@startLine:startColumn-endLine:endColumn`, which names no offsets.
private func range(_ startLine: Int, _ startColumn: Int, _ endLine: Int, _ endColumn: Int) -> SourceRange {
    SourceRange(
        SourceLocation(line: startLine, column: startColumn, offset: 0),
        SourceLocation(line: endLine, column: endColumn, offset: 0),
    )
}

private let malformedIR = [
    MalformedIR(
        testDescription: "a character no token starts with",
        text: "struct Pair {\n  count: Int#\n}",
        error: IRTextError(line: 2, column: 13, message: "unexpected character '#'"),
    ),
    MalformedIR(
        testDescription: "a quoted name with no closing quote",
        text: "main \"main()\nfunc",
        error: IRTextError(line: 1, column: 6, message: "a quoted name with no closing quote"),
    ),
    MalformedIR(
        testDescription: "a token where another is expected",
        text: "func \"f()\"() Void",
        error: IRTextError(line: 1, column: 14, message: "expected '->', found 'Void'"),
    ),
    MalformedIR(
        testDescription: "a type no struct declares",
        text: "struct Pair {\n  count: Count\n}",
        error: IRTextError(line: 2, column: 10, message: "no type is named 'Count'"),
    ),
    MalformedIR(
        testDescription: "an array type without 'of'",
        text: "struct Pair {\n  counts: [2 Int]\n}",
        error: IRTextError(line: 2, column: 14, message: "expected 'of', found 'Int'"),
    ),
    MalformedIR(
        testDescription: "a struct declared twice",
        text: "struct Pair {\n}\nstruct Pair {\n}",
        error: IRTextError(line: 3, column: 8, message: "struct 'Pair' is declared twice"),
    ),
    MalformedIR(
        testDescription: "a call of a function the text doesn't declare",
        text: "func \"f()\"() -> Void {\nbb0:\n  _ = call \"g()\"() @1:1-1:2\n  return\n}",
        error: IRTextError(line: 3, column: 12, message: "no function is named \"g()\""),
    ),
    MalformedIR(
        testDescription: "a call of a built-in the prelude doesn't have",
        text: "func \"f()\"() -> Void {\nbb0:\n  _ = call builtin \"print()\"() @1:1-1:2\n  return\n}",
        error: IRTextError(line: 3, column: 20, message: "no built-in is named \"print()\""),
    ),
    MalformedIR(
        testDescription: "an operation the IR doesn't have",
        text: "func \"f()\"() -> Void {\nbb0:\n  _ = shift 1, 2 @1:1-1:2\n  return\n}",
        error: IRTextError(line: 3, column: 7, message: "no operation is named 'shift'"),
    ),
    MalformedIR(
        testDescription: "a local numbered out of order",
        text: "func \"f()\"() -> Void {\n  temp %1: Int\nbb0:\n  return\n}",
        error: IRTextError(line: 2, column: 9, message: "expected the local %0"),
    ),
    MalformedIR(
        testDescription: "a use of a local the function doesn't declare",
        text: "func \"f()\"() -> Void {\n  temp %0: Int\nbb0:\n  return read %1 @1:1-1:2\n}",
        error: IRTextError(line: 4, column: 16, message: "no local is numbered %1"),
    ),
    MalformedIR(
        testDescription: "an access that no statement begins",
        text: "func \"f()\"() -> Void {\nbb0:\n  end a2\n  return\n}",
        error: IRTextError(line: 3, column: 7, message: "no statement begins a2"),
    ),
    MalformedIR(
        testDescription: "an access begun twice",
        text: "func \"f()\"() -> Void {\n  temp %0: Int\nbb0:\n  begin a0 read static %0 @1:1-1:2\n"
            + "  begin a0 read static %0 @1:1-1:2\n  return\n}",
        error: IRTextError(line: 5, column: 9, message: "a0 is begun twice"),
    ),
    MalformedIR(
        testDescription: "a block labelled out of order",
        text: "func \"f()\"() -> Void {\nbb1:\n  return\n}",
        error: IRTextError(line: 2, column: 1, message: "expected the label bb0"),
    ),
    MalformedIR(
        testDescription: "a jump to a block the function doesn't have",
        text: "func \"f()\"() -> Void {\nbb0:\n  goto bb3\n}",
        error: IRTextError(line: 3, column: 8, message: "no block is labelled bb3"),
    ),
    MalformedIR(
        testDescription: "a declaration of a local the function doesn't hold",
        text: "func \"f()\"() -> Void {\nbb0:\n  declare %0\n}",
        error: IRTextError(line: 3, column: 12, message: "no local is numbered %0"),
    ),
    MalformedIR(
        testDescription: "a block that ends without a terminator",
        text: "func \"f()\"() -> Void {\nbb0:\n}",
        error: IRTextError(line: 3, column: 1, message: "expected a statement or a terminator, found '}'"),
    ),
    MalformedIR(
        testDescription: "an Int constant too large for an Int",
        text: "func \"f()\"() -> Int {\nbb0:\n  return 9223372036854775808\n}",
        error: IRTextError(line: 3, column: 10, message: "9223372036854775808 isn't an Int"),
    ),
    MalformedIR(
        testDescription: "the function a run starts at named twice",
        text: "func \"f()\"() -> Void\nmain \"f()\"\nmain \"f()\"",
        error: IRTextError(line: 3, column: 1, message: "the function a run starts at is named twice"),
    ),
]
