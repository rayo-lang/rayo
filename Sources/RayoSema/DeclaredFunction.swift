import RayoSyntax

/// A function as the checker declares it: what a call needs to know about it, and where its body comes from.
struct DeclaredFunction {
    /// Where a declared function's body comes from.
    enum Kind {
        /// A function the source writes, whose declaration holds its body.
        case written(FuncDecl)

        /// The kind the checked program gives the function.
        var functionKind: FunctionKind {
            switch self {
            case .written: .written
            }
        }
    }

    var signature: Signature
    var kind: Kind
}
