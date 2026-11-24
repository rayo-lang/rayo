import RayoSyntax

/// What takes the value that stands in a position, where that decides how the source writes a place there: a call's
/// parameter, or the declaration of a local.
enum Recipient {
    case parameter(ArgumentParameter)
    /// The value of a declaration of the given kind, which the local it declares takes.
    case declaration(DeclarationKind)

    /// The parameter that takes the value, where it borrows the value for change; nil for any other recipient.
    var mutableParameter: ArgumentParameter? {
        if case .parameter(let parameter) = self, parameter.convention == .mutable { parameter } else { nil }
    }
}
