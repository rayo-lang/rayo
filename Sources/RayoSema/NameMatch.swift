/// What an unqualified name stands for where a function body uses it.
enum NameMatch {
    /// A local or a parameter.
    case inScope(ScopeEntry)
    /// The module's functions of that name, the prelude's among them.
    case functions([Signature])
    /// The module's struct of that name.
    case structure(StructID)

    /// What a use of the name of `type`, one of the module's types, stands for.
    init(type: DeclaredType) {
        switch type {
        case .structure(let id): self = .structure(id)
        }
    }
}
