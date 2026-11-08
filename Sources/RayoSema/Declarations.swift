import RayoSyntax

/// What a call needs to know about the function it calls.
struct Signature {
    var name: String
    var parameters: [RayoType]
    var result: RayoType

    static let print = Signature(name: "print", parameters: [.int], result: .void)
}

/// The names a function body sees beyond its own locals: the prelude's, and the file's own declarations.
struct Declarations {
    /// The functions a program can name.
    let functionNames: Set<String> = ["print", "main"]

    func resolve(_ type: TypeExpr, reporting errors: inout Diagnostics) -> RayoType? {
        switch type {
        case .named("Int", _):
            return .int
        case .named("Bool", _):
            return .bool
        case .named("Void", _), .void:
            return .void
        case .named(let name, let range):
            errors.error("'\(name)' isn't a type", at: range)
            return nil
        }
    }
}
