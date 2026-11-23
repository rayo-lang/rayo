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

/// The IR statements that print the Int that `place` holds, through an access no other statement begins.
func printInt(_ place: String, through access: Int) -> String {
    printStatements(of: "Int", at: place, through: access)
}

/// The IR statements that print the UInt that `place` holds.
func printUInt(_ place: String, through access: Int) -> String {
    printStatements(of: "UInt", at: place, through: access)
}

/// The IR statements that print the Bool that `place` holds.
func printBool(_ place: String, through access: Int) -> String {
    printStatements(of: "Bool", at: place, through: access)
}

/// A print of `place` through a read access, begun before the call and ended after it, as the ownership stage gives it.
private func printStatements(of type: String, at place: String, through access: Int) -> String {
    let call = #"_ = call builtin "print(_: &\#(type))"(a\#(access)) @1:1-1:2"#
    return "begin a\(access) read \(place) @1:1-1:2\n\(call)\nend a\(access)"
}
