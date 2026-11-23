import Testing
import RayoIR
import RayoCheckedProgram
import RayoSource

// The tests write their IR as text. A test names the source ranges it checks on line 2, each at the column it numbers
// it by, as in `read %0 @2:3-2:3`; every other range is `@1:1-1:1`, ahead of them all.

/// The range at `column` of line 2, where a test names the uses it checks.
func at(_ column: Int) -> SourceRange {
    let location = SourceLocation(line: 2, column: column, offset: 0)
    return SourceRange(location, location)
}

/// The program `text` writes, which must read as Rayo IR and keep the rules of the IR that `stage` gives.
func parsedIR(_ text: String, from stage: IRStage) throws -> IRProgram {
    let program = try IRParser.program(from: text)
    if let violation = IRVerifier.verify(program, from: stage) { throw violation }
    return program
}

/// A program of `functions`, the first of them the one a run starts at, which declares a `Shot` of an Int `range` and
/// a `Hit`, and a `Hit` of an Int `damage`, with the primary initializer of each after the functions. It keeps the
/// rules of the IR that `stage` gives: lowering, for IR the ownership stage checks, or the ownership stage, for IR it
/// is expected to give.
func program(of functions: [(name: String, text: String)], from stage: IRStage) throws -> IRProgram {
    try parsedIR("""
        struct Shot {
          var range: Int
          var hit: Hit
        }
        struct Hit {
          var damage: Int
        }
        main "\(functions[0].name)"
        \(functions.map(\.text).joined(separator: "\n"))
        init "Shot(range: Int, hit: Hit)"(range: Int, hit: Hit) -> Shot
        init "Hit(damage: Int)"(damage: Int) -> Hit
        """, from: stage)
}

/// The function `name`, made of `blocks`, whose locals are the `var`s `x` (`%0`) and `y` (`%1`), the `let` `k` (`%2`)
/// and a temporary (`%3`), all Ints, then the `var`s `h` (`%4`), a `Hit`, `s` (`%5`), a `Shot`, `b` (`%6`), a Bool,
/// and `a` (`%7`), two `Hit`s, and a UInt temporary (`%8`). It takes no parameters, and returns `result`.
func function(
    _ blocks: String, named name: String = "f()", result: String = "Void",
) -> (name: String, text: String) {
    let text = """
        func "\(name)"() -> \(result) {
          var %0 x: Int @1:1-1:1
          var %1 y: Int @1:1-1:1
          let %2 k: Int @1:1-1:1
          temp %3: Int
          var %4 h: Hit @1:1-1:1
          var %5 s: Shot @1:1-1:1
          var %6 b: Bool @1:1-1:1
          var %7 a: [2 of Hit] @1:1-1:1
          temp %8: UInt
        \(blocks)
        }
        """
    return (name, text)
}

/// Stores a new `Hit` in `h`, then a new `Shot` that takes it in `s`, which the source names at `column` of line 2, or
/// at `1:1` where there is none.
func storeShot(at column: Int? = nil) -> String {
    let range = column.map { "@2:\($0)-2:\($0)" } ?? "@1:1-1:1"
    return """
          %4 @1:1-1:1 = call "Hit(damage: Int)"(7) @1:1-1:1
          %5 \(range) = call "Shot(range: Int, hit: Hit)"(4, move %4 \(range)) @1:1-1:1
        """
}

/// The functions that the tests' blocks call, which have no bodies. Each `change` may change its first argument, and
/// the others borrow theirs.
let callees = [
    (name: "g(_: &Int, _: &Int)", text: #"func "g(_: &Int, _: &Int)"(_: &Int, _: &Int) -> Void"#),
    (name: "take(_: &Int, _: &Hit)", text: #"func "take(_: &Int, _: &Hit)"(_: &Int, _: &Hit) -> Void"#),
    (name: "double(_: &Int)", text: #"func "double(_: &Int)"(_: &Int) -> Int"#),
    (
        name: "change(_: mutable &Int, _: &Int)",
        text: #"func "change(_: mutable &Int, _: &Int)"(_: mutable &Int, _: &Int) -> Void"#,
    ),
    (
        name: "change(_: mutable &Int, _: &Hit)",
        text: #"func "change(_: mutable &Int, _: &Hit)"(_: mutable &Int, _: &Hit) -> Void"#,
    ),
]

/// The function `loops()`, which runs `loops` loops one after another. Each counts its own UInt `c` up to eight, and
/// on each pass declares its own `let` `v`, gives it the count as an Int, and prints it.
func loopingFunction(loops: Int) -> (name: String, text: String) {
    let locals = (0..<loops).map { loop in
        let (counter, test, value) = (3 * loop, 3 * loop + 1, 3 * loop + 2)
        return """
              var %\(counter) c\(loop): UInt @1:1-1:1
              temp %\(test): Bool
              let %\(value) v\(loop): Int @1:1-1:1
            """
    }
    // Each loop starts its count in a block of its own, and declares each local where lowering would.
    let blocks = (0..<loops).map { loop in
        let (counter, test, value) = (3 * loop, 3 * loop + 1, 3 * loop + 2)
        let (start, header, body) = (3 * loop, 3 * loop + 1, 3 * loop + 2)
        return """
            bb\(start):
              declare %\(counter)
              %\(counter) @1:1-1:1 = operand UInt 0 @1:1-1:1
              goto bb\(header)
            bb\(header):
              declare %\(test)
              %\(test) @1:1-1:1 = less read %\(counter) @1:1-1:1, UInt 8 @1:1-1:1
              branch read %\(test) @1:1-1:1, bb\(body), bb\(start + 3)
            bb\(body):
              declare %\(value)
              %\(value) @1:1-1:1 = call builtin "Int(_: UInt)"(read %\(counter) @1:1-1:1) @1:1-1:1
              begin a\(loop) read %\(value) @1:1-1:1
              _ = call builtin "print(_: &Int)"(a\(loop)) @1:1-1:1
              %\(counter) @1:1-1:1 = add checked read %\(counter) @1:1-1:1, UInt 1 @1:1-1:1
              goto bb\(header)
            """
    }
    let text = """
        func "loops()"() -> Void {
        \(locals.joined(separator: "\n"))
        \(blocks.joined(separator: "\n"))
        bb\(3 * loops):
          return
        }
        """
    return ("loops()", text)
}
