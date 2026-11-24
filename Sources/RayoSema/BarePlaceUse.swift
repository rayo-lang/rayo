/// What a parameter that owns its argument does with a place written bare, of a type that isn't implicitly copyable.
enum BarePlaceUse {
    /// The place's value moves into the parameter, as it does into a struct's primary initializer.
    case moves
    /// The parameter reads the value and the place keeps it, as `.init(repeating:)` copies it into each element.
    case reads
    /// The call reports the place, since the parameter takes one only marked with `consume` or `copy`.
    case needsMark
}
