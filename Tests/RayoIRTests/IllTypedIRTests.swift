import RayoIR
import RayoSema
import Testing

/// IR that no lowering of a checked program makes, and what the verifier says is wrong with it.
struct IllTypedIR: CustomTestStringConvertible, Sendable {
    let testDescription: String
    /// The IR, as text.
    let text: String
    /// The name of the function the violation is in.
    let function: String
    let message: String
}

@Suite("IR that breaks its types")
struct IllTypedIRTests {
    @Test(arguments: illTypedIR)
    func `is a violation that names its function and says what is wrong`(ir: IllTypedIR) throws {
        let program = try IRParser.program(from: ir.text)
        #expect(IRVerifier.verify(program) == IRViolation(function: ir.function, message: ir.message))
    }

    @Test func `IR that keeps its types has no violation`() throws {
        let program = try lowered("""
            struct Pair(var count: Int, var flag: Bool)
            func twice(_ n: Int) -> Int { n * 2 }
            func main() {
                var pair = Pair(count: -twice(3) % 4, flag: !(1 < 2))
                pair.count += 1
                if pair.flag == false && pair.count != 0 { print(pair.count / 2) }
                while pair.count >= 0 { pair.count -= 1 }
                print(pair.flag)
            }
            """)
        #expect(IRVerifier.verify(program) == nil)
    }

    @Test func `a wrapping operator is named as one`() throws {
        let program = try IRParser.program(from: main("""
              temp %0: Bool
              temp %1: Int
              temp %2: Int
            bb0:
              %2 @1:1-1:2 = add wrapping read %0 @1:1-1:2, read %1 @1:1-1:2 @1:1-1:2
              return
            """))
        let message = "the IR gives 'wrapping +' an operand of type Bool, where it takes Int"
        #expect(IRVerifier.verify(program) == IRViolation(function: "main()", message: message))
    }
}

/// A program that declares `Pair`, a struct of one Int `count`, and whose `main` holds `body`'s locals and blocks.
private func main(_ body: String, after functions: String = "") -> String {
    """
    struct Pair {
      count: Int
    }
    main "main()"
    func "main()"() -> Void {
    \(body)
    }
    \(functions)
    """
}

/// A program whose `main` holds temporaries of `operands`, and then of `result`, and computes `value` into the last.
private func computing(_ value: String, on operands: [String], into result: String) -> String {
    let locals = (operands + [result]).enumerated().map { "  temp %\($0): \($1)" }.joined(separator: "\n")
    return main("\(locals)\nbb0:\n  %\(operands.count) @1:1-1:2 = \(value) @1:1-1:2\n  return")
}

private let illTypedIR = [
    IllTypedIR(
        testDescription: "an operator given an operand of a type it doesn't take",
        text: computing("add checked read %0 @1:1-1:2, read %1 @1:1-1:2", on: ["Bool", "Int"], into: "Int"),
        function: "main()",
        message: "the IR gives '+' an operand of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "a division by a Bool",
        text: computing("divide checked read %0 @1:1-1:2, read %1 @1:1-1:2", on: ["Int", "Bool"], into: "Int"),
        function: "main()",
        message: "the IR gives '/' an operand of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "a remainder of a Bool",
        text: computing("remainder read %0 @1:1-1:2, read %1 @1:1-1:2", on: ["Bool", "Int"], into: "Int"),
        function: "main()",
        message: "the IR gives '%' an operand of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "negation of a Bool",
        text: computing("negate checked read %0 @1:1-1:2", on: ["Bool"], into: "Int"),
        function: "main()",
        message: "the IR gives '-' an operand of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "'!' of an Int",
        text: computing("not read %0 @1:1-1:2", on: ["Int"], into: "Bool"),
        function: "main()",
        message: "the IR gives '!' an operand of type Int, where it takes Bool",
    ),
    IllTypedIR(
        testDescription: "a comparison of a Bool with an Int",
        text: computing("equal read %0 @1:1-1:2, read %1 @1:1-1:2", on: ["Bool", "Int"], into: "Bool"),
        function: "main()",
        message: "the IR gives '==' an operand of type Int, where it takes Bool",
    ),
    IllTypedIR(
        testDescription: "a comparison of an Int with a Bool",
        text: computing("less read %0 @1:1-1:2, read %1 @1:1-1:2", on: ["Int", "Bool"], into: "Bool"),
        function: "main()",
        message: "the IR gives '<' an operand of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "an ordering of two Bools",
        text: computing("less read %0 @1:1-1:2, read %1 @1:1-1:2", on: ["Bool", "Bool"], into: "Bool"),
        function: "main()",
        message: "the IR gives '<' an operand of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "a comparison of two structs",
        text: computing("equal read %0 @1:1-1:2, read %1 @1:1-1:2", on: ["Pair", "Pair"], into: "Bool"),
        function: "main()",
        message: "the IR gives '==' an operand of type Pair, where it takes Int or Bool",
    ),
    IllTypedIR(
        testDescription: "a branch on an Int",
        text: main("""
              temp %0: Int
            bb0:
              branch read %0 @1:1-1:2, bb1, bb1
            bb1:
              return
            """),
        function: "main()",
        message: "the IR branches on a value of type Int, where it takes Bool",
    ),
    IllTypedIR(
        testDescription: "a store of an Int in a Bool",
        text: computing("use read %0 @1:1-1:2", on: ["Int"], into: "Bool"),
        function: "main()",
        message: "the IR stores a value of type Int in a place of type Bool",
    ),
    IllTypedIR(
        testDescription: "a store of a Bool in an Int field",
        text: main("""
              temp %0: Bool
              temp %1: Pair
            bb0:
              %1.0 @1:1-1:2 = use read %0 @1:1-1:2 @1:1-1:2
              return
            """),
        function: "main()",
        message: "the IR stores a value of type Bool in a place of type Int",
    ),
    IllTypedIR(
        testDescription: "a store in a field of an Int",
        text: main("""
              temp %0: Int
              temp %1: Int
            bb0:
              %1.0 @1:1-1:2 = use read %0 @1:1-1:2 @1:1-1:2
              return
            """),
        function: "main()",
        message: "the IR names field 0 of a value of type Int",
    ),
    IllTypedIR(
        testDescription: "a call given an argument of a type its function doesn't take",
        text: main("""
              temp %0: Bool
            bb0:
              _ = call builtin "print(_: Int)"(read %0 @1:1-1:2) @1:1-1:2
              return
            """),
        function: "main()",
        message: "the IR passes 'print(_: Int)' an argument of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "a call of the Bool print given an Int",
        text: main("bb0:\n  _ = call builtin \"print(_: Bool)\"(1) @1:1-1:2\n  return"),
        function: "main()",
        message: "the IR passes 'print(_: Bool)' an argument of type Int, where it takes Bool",
    ),
    IllTypedIR(
        testDescription: "a call given too few arguments",
        text: main("bb0:\n  _ = call builtin \"print(_: Int)\"() @1:1-1:2\n  return"),
        function: "main()",
        message: "the IR passes 'print(_: Int)' 0 arguments, where it takes 1",
    ),
    IllTypedIR(
        testDescription: "a call given too many arguments",
        text: main("bb0:\n  _ = call builtin \"print(_: Int)\"(1, 2) @1:1-1:2\n  return"),
        function: "main()",
        message: "the IR passes 'print(_: Int)' 2 arguments, where it takes 1",
    ),
    IllTypedIR(
        testDescription: "a call given one argument too few",
        text: main("bb0:\n  _ = call \"f(_:_:)\"(1) @1:1-1:2\n  return", after: """
            func "f(_:_:)"(Int, Int) -> Void {
              temp %0: Int
              temp %1: Int
            bb0:
              return
            }
            """),
        function: "main()",
        message: "the IR passes 'f(_:_:)' 1 argument, where it takes 2",
    ),
    IllTypedIR(
        testDescription: "a store of what a call that returns nothing gives",
        text: main("  temp %0: Int\nbb0:\n  %0 @1:1-1:2 = call \"f()\"() @1:1-1:2\n  return", after: """
            func "f()"() -> Void {
            bb0:
              return
            }
            """),
        function: "main()",
        message: "the IR stores a value of type Void in a place of type Int",
    ),
    IllTypedIR(
        testDescription: "a return of a Bool from a function that returns an Int",
        text: main("bb0:\n  return", after: """
            func "f()"() -> Int {
              temp %0: Bool
            bb0:
              return read %0 @1:1-1:2
            }
            """),
        function: "f()",
        message: "the IR returns a value of type Bool from a function that returns Int",
    ),
    IllTypedIR(
        testDescription: "a return of nothing from a function that returns an Int",
        text: main("bb0:\n  return", after: """
            func "f()"() -> Int {
              temp %0: Bool
            bb0:
              return
            }
            """),
        function: "f()",
        message: "the IR returns nothing from a function that returns Int",
    ),
    IllTypedIR(
        testDescription: "a return of a value from a function that returns Void",
        text: main("bb0:\n  return", after: """
            func "f()"() -> Void {
              temp %0: Bool
            bb0:
              return read %0 @1:1-1:2
            }
            """),
        function: "f()",
        message: "the IR returns a value of type Bool from a function that returns Void",
    ),
    IllTypedIR(
        testDescription: "a primary initializer that takes fewer values than its struct has fields",
        text: main("bb0:\n  return", after: "init \"Pair()\"() -> Pair"),
        function: "Pair()",
        message: "the IR's primary initializer of 'Pair' takes (), where its fields are (Int)",
    ),
    IllTypedIR(
        testDescription: "a primary initializer that takes a value of another type than its struct's field",
        text: main("bb0:\n  return", after: "init \"Pair(count: Bool)\"(Bool) -> Pair"),
        function: "Pair(count: Bool)",
        message: "the IR's primary initializer of 'Pair' takes (Bool), where its fields are (Int)",
    ),
    IllTypedIR(
        testDescription: "a read of a field of an Int",
        text: computing("use read %0.0 @1:1-1:2", on: ["Int"], into: "Int"),
        function: "main()",
        message: "the IR names field 0 of a value of type Int",
    ),
    IllTypedIR(
        testDescription: "a read of a field that a struct doesn't have",
        text: computing("use read %0.1 @1:1-1:2", on: ["Pair"], into: "Int"),
        function: "main()",
        message: "the IR names field 1 of a value of type Pair",
    ),
]
