/// What an unqualified name stands for where a function body uses it.
enum NameMatch {
    /// A local or a parameter.
    case inScope(ScopeEntry)
    /// A field of `self`, which the parameter `selfParameter` holds: the field at `index` in its struct's declaration.
    /// The bare name names the same place as `self.name`.
    case instanceField(selfParameter: LocalID, index: Int, Field)
    /// The module's functions of that name, the prelude's among them.
    case functions([Signature])
    /// The module's type of that name, or the prelude's that no type or function of the module shadows.
    case type(RayoType)
    /// A function or a type of the module whose declaration failed, which was reported there, so its uses report
    /// nothing more.
    case failed

    /// Whether the name reaches a declaration that failed, which taints the body that uses it: a local or a
    /// parameter, or a function or a type of the module. A parameter whose type failed was reported with its
    /// function's signature, outside the body, so nothing but its use taints the body.
    var reachesFailedDeclaration: Bool {
        switch self {
        case .failed, .inScope(.failed): true
        // A call might have meant any of the functions, so one that failed is reached among them.
        case .functions(let functions): functions.contains(where: \.hasFailed)
        case .inScope(.local), .instanceField, .type: false
        }
    }
}
