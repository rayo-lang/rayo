/// What a bare name stands for where a position expects a place and the name names none.
enum NonPlaceName {
    /// `_`, which only drops a value or leaves a parameter unnamed.
    case underscore
    /// The module's functions of the name.
    case function
    /// A type's name.
    case type
}
