/// The structs the programs that the tests run build, with their primary initializers: a Pair of two Ints, which
/// passes and returns as its two scalars; a Trio of two Ints and a Bool, which is large, so it passes as a pointer and
/// returns through a slot; and a Box of a Pair and three Ints, whose fields lead to places of several steps.
let programStructs = """
    struct Pair {
      var a: Int
      var b: Int
    }
    struct Trio {
      var a: Int
      var b: Int
      var c: Bool
    }
    struct Box {
      var pair: Pair
      var items: [3 of Int]
    }
    init "Pair(a: Int, b: Int)"(a: Int, b: Int) -> Pair
    init "Trio(a: Int, b: Int, c: Bool)"(a: Int, b: Int, c: Bool) -> Trio

    """

/// The IR statement that prints the Int that `place` holds, such as `%0.1`.
func printInt(_ place: String) -> String {
    #"_ = call builtin "print(_: Int)"(read \#(place) @1:1-1:2) @1:1-1:2"#
}

/// The IR statement that prints the UInt that `place` holds.
func printUInt(_ place: String) -> String {
    #"_ = call builtin "print(_: UInt)"(read \#(place) @1:1-1:2) @1:1-1:2"#
}

/// The IR statement that prints the Bool that `place` holds.
func printBool(_ place: String) -> String {
    #"_ = call builtin "print(_: Bool)"(read \#(place) @1:1-1:2) @1:1-1:2"#
}
