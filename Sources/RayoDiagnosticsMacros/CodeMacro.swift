import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Code`, which marks a case for `@Diagnostics` to read, and adds nothing itself. Written anywhere else,
/// it is an error, since nothing would read it.
public struct CodeMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        // A `@Code` on anything but a case of a `@Diagnostics` enum is one no table reads.
        if !declaration.is(EnumCaseDeclSyntax.self) || !isInTable(context) {
            context.diagnose(Diagnostic(node: node, message: CodeTableError.codeOutsideTable))
        }
        return []
    }

    /// Whether the declaration that `context` expands in sits directly inside an enum marked `@Diagnostics`.
    private static func isInTable(_ context: some MacroExpansionContext) -> Bool {
        // Outside an enum there is no table.
        guard let table = context.lexicalContext.first?.as(EnumDeclSyntax.self) else { return false }

        return table.attributes.contains { element in
            // An `#if` among the enum's attributes is no `@Diagnostics`.
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            return isDiagnostics(attribute.attributeName)
        }
    }

    /// Whether `name` names `@Diagnostics`, alone or after its module's name.
    private static func isDiagnostics(_ name: TypeSyntax) -> Bool {
        // `@Diagnostics` written alone.
        if let identifier = name.as(IdentifierTypeSyntax.self) { return identifier.name.text == "Diagnostics" }
        // `@Diagnostics` after its module's name, as in `@RayoDiagnostics.Diagnostics`; any other name isn't it.
        return name.as(MemberTypeSyntax.self)?.name.text == "Diagnostics"
    }
}
