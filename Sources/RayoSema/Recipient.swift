import RayoSyntax

/// What takes the value that stands in a position, where that decides how the source writes a place there: a call's
/// parameter, or the declaration of a local. A parameter that borrows its argument, and a `ref let`, take a place
/// written `&p`; a `let` or a `var` takes one written `copy p` or `consume p`, and no reference.
enum Recipient {
    case parameter(ArgumentParameter)
    /// The value of a declaration of the given kind, which the local it declares takes.
    case declaration(DeclarationKind)
}
