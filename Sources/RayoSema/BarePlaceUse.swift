/// How a parameter that owns its argument takes a place written bare, of a type that isn't implicitly copyable.
enum BarePlaceUse {
    /// The place's value moves into the parameter, as it does into a struct's primary initializer.
    case moves
    /// The parameter reads the value and the place keeps it, as `.init(repeating:)` copies it into each element.
    case reads
    /// The parameter takes a place only marked with `consume` or `copy`, so a bare one is reported.
    case needsMark
}
