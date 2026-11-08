import RayoSyntax

/// What a call needs to know about the function it calls.
struct Signature {
    struct Parameter {
        var label: String?
        /// Nil for a parameter that takes a value of any type.
        var type: RayoType?
    }

    var name: String
    var parameters: [Parameter]
    var result: RayoType

    static let print = Signature(name: "print", parameters: [Parameter(label: nil, type: nil)], result: .void)
}

/// The names a function body sees beyond its own locals: the prelude's, and the file's own declarations.
struct Declarations {
    /// The functions a program can name.
    let functionNames: Set<String> = ["print", "main"]

    func resolve(_ type: TypeExpr, reporting errors: inout Diagnostics) -> RayoType? {
        switch type {
        case .named("Int", let arguments, _) where arguments.isEmpty:
            return .int
        case .named("Bool", let arguments, _) where arguments.isEmpty:
            return .bool
        case .named("Void", let arguments, _) where arguments.isEmpty:
            return .void
        case .void:
            return .void
        default:
            errors.unsupported("the type '\(type)'", at: type.range)
            return nil
        }
    }
}
