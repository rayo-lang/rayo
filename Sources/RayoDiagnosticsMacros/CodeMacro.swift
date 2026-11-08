import SwiftSyntax
import SwiftSyntaxMacros

/// `@Code`, which marks a case for `@Diagnostics` to read, and adds nothing itself.
public struct CodeMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        []
    }
}
