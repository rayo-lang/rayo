/// What declares a parameter, which decides what its argument is for.
package enum ParameterKind: Hashable, Sendable {
    /// A function's or a built-in's parameter.
    case function
    /// A parameter of a struct's primary initializer, whose argument the field of its label takes.
    case field
    /// The parameter of an array's `init(repeating:)`, whose argument each element of the array copies.
    case repeatedElement
}
