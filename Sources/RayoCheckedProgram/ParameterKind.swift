/// What declares a parameter, which decides what its argument is for.
package enum ParameterKind: Hashable, Sendable, CaseIterable {
    /// A function's, a built-in's or a struct's primary initializer's parameter.
    case function
    /// The parameter of an array's `init(repeating:)`, whose argument each element of the array copies.
    case repeatedElement
}
