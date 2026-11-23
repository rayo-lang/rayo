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

/// The IR statements that print the Int that `place` holds, such as `%0.1`, through the access `aN`, where `N` is
/// `access`, which no other statement of the function begins.
func printInt(_ place: String, through access: Int) -> String {
    printStatements(of: "Int", at: place, through: access)
}

/// The IR statements that print the UInt that `place` holds, through the access `access` numbers.
func printUInt(_ place: String, through access: Int) -> String {
    printStatements(of: "UInt", at: place, through: access)
}

/// The IR statements that print the Bool that `place` holds, through the access `access` numbers.
func printBool(_ place: String, through access: Int) -> String {
    printStatements(of: "Bool", at: place, through: access)
}

/// The IR statements that print the value of `type` that `place` holds, as the ownership stage gives a print its
/// argument: a read access to the place, numbered `access`, begun as the call begins and ended once it returns.
private func printStatements(of type: String, at place: String, through access: Int) -> String {
    let call = #"_ = call builtin "print(_: &\#(type))"(a\#(access)) @1:1-1:2"#
    return "begin a\(access) read \(place) @1:1-1:2\n\(call)\nend a\(access)"
}
