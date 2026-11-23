/// The fastest time `measure` gives over `short` and over `long`, of `runs` runs each. The runs take the two in turn,
/// so that a runner busy with other work during one run slows neither one's time.
func fastestTimes<Input, Failure: Error>(
    over short: Input, _ long: Input, runs: Int, measuring measure: (Input) throws(Failure) -> Duration,
) throws(Failure) -> (short: Duration, long: Duration) {
    var shortTime = Duration.seconds(Int64.max)
    var longTime = Duration.seconds(Int64.max)
    for _ in 0..<runs {
        shortTime = min(shortTime, try measure(short))
        longTime = min(longTime, try measure(long))
    }
    return (shortTime, longTime)
}

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
