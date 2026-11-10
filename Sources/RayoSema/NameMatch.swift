/// What an unqualified name stands for where a function body uses it.
enum NameMatch {
    /// A local or a parameter.
    case inScope(ScopeEntry)
    /// The module's functions of that name, the prelude's among them.
    case functions([Signature])
    /// The module's struct of that name, whose primary initializer a call of the name calls.
    case type(initializer: Signature)
}
