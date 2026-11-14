import RayoIR
import RayoSource

// The tests write their IR as text. A test names the source ranges it checks on line 2, each at the column it numbers
// it by, as in `read %0 @2:3-2:3`; every other range is `@1:1-1:1`, ahead of them all.

/// The range at `column` of line 2, where a test names the uses it checks.
func at(_ column: Int) -> SourceRange {
    let location = SourceLocation(line: 2, column: column, offset: 0)
    return SourceRange(location, location)
}

/// The program `text` writes, which must read as Rayo IR and keep the IR's types.
func parsedIR(_ text: String) throws -> IRProgram {
    let program = try IRParser.program(from: text)
    if let violation = IRVerifier.verify(program) { throw violation }
    return program
}

/// A program of `functions`, the first of them the one a run starts at, which declares a `Shot` of an Int `range` and
/// a `Hit`, and a `Hit` of an Int `damage`, with the primary initializer of each after the functions.
func program(of functions: [(name: String, text: String)]) throws -> IRProgram {
    try parsedIR("""
        struct Shot {
          range: Int
          hit: Hit
        }
        struct Hit {
          damage: Int
        }
        main "\(functions[0].name)"
        \(functions.map(\.text).joined(separator: "\n"))
        init "Shot(range: Int, hit: Hit)"(Int, Hit) -> Shot
        init "Hit(damage: Int)"(Int) -> Hit
        """)
}

/// The function `name`, made of `blocks`, whose locals are the `var`s `x` (`%0`) and `y` (`%1`), the `let` `k` (`%2`)
/// and a temporary (`%3`), all Ints, then the `var`s `h` (`%4`), a `Hit`, `s` (`%5`), a `Shot`, `b` (`%6`), a Bool,
/// and `a` (`%7`), two `Hit`s, and a UInt temporary (`%8`). It returns `result`, and its parameters are of
/// `parameters`' types, which its first locals hold.
func function(
    _ blocks: String, named name: String = "f()", parameters: String = "", result: String = "Void",
) -> (name: String, text: String) {
    let text = """
        func "\(name)"(\(parameters)) -> \(result) {
          var %0 x: Int
          var %1 y: Int
          let %2 k: Int
          temp %3: Int
          var %4 h: Hit
          var %5 s: Shot
          var %6 b: Bool
          var %7 a: [2 of Hit]
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
