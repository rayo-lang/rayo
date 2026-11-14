/// What an access may do with the place it reaches, which decides the other accesses it conflicts with.
public enum AccessKind: Hashable, Sendable {
    /// Reads the place and changes nothing, as a borrowed argument does. Other reads may overlap it.
    case read
    /// May change the place, as a `mutable` argument does. No other access may overlap it.
    case modify
}
