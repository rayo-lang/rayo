import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Code`, which marks a case for `@Diagnostics` to read, and adds nothing itself. Written anywhere else,
/// it is an error, since nothing would read it.
public struct CodeMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        let table = context.lexicalContext.first?.as(EnumDeclSyntax.self)
        let isInTable = table?.attributes.contains { attribute in
            attribute.as(AttributeSyntax.self).map { isDiagnostics($0.attributeName) } ?? false
        } ?? false
        if !declaration.is(EnumCaseDeclSyntax.self) || !isInTable {
            context.diagnose(Diagnostic(node: node, message: CodeTableError.codeOutsideTable))
        }
        return []
    }

    /// Whether `name` names `@Diagnostics`, alone or after its module's name.
    private static func isDiagnostics(_ name: TypeSyntax) -> Bool {
        if let identifier = name.as(IdentifierTypeSyntax.self) { return identifier.name.text == "Diagnostics" }
        return name.as(MemberTypeSyntax.self)?.name.text == "Diagnostics"
    }
}
