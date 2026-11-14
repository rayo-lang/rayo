/// What an unqualified name stands for where a function body uses it.
enum NameMatch {
    /// A local or a parameter.
    case inScope(ScopeEntry)
    /// The module's functions of that name, the prelude's among them.
    case functions([Signature])
    /// The module's struct of that name.
    case structure(StructID)
    /// A function or a type of the module whose declaration failed, which was reported there, so its uses report
    /// nothing more.
    case failed

    /// What a use of the name of `type`, one of the module's types, stands for.
    init(type: DeclaredType) {
        switch type {
        case .structure(let id): self = .structure(id)
        case .failed: self = .failed
        }
    }

    /// Whether the name reaches a function or a type of the module whose declaration failed, which taints the body
    /// that uses it. A local whose declaration failed was reported in the same body, which that tainted already.
    var reachesFailedDeclaration: Bool {
        switch self {
        case .failed: true
        // A call might have meant any of the functions, so one that failed is reached among them.
        case .functions(let functions): functions.contains(where: \.hasFailed)
        case .inScope, .structure: false
        }
    }
}
