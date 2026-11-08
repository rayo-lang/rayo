import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing
@testable import RayoDiagnosticsMacros

private let macros = [
    "Diagnostics": MacroSpec(type: DiagnosticsMacro.self),
    "Code": MacroSpec(type: CodeMacro.self),
]

/// Expands `source`, which must fail with `errors`, each at its line and column, and expand to `expanded`.
private func expectErrors(_ source: String, expanded: String, _ errors: [(CodeTableError, line: Int, column: Int)],
                          sourceLocation: SourceLocation = #_sourceLocation) {
    assertMacroExpansion(
        source,
        expandedSource: expanded,
        diagnostics: errors.map { DiagnosticSpec(message: $0.0.message, line: $0.line, column: $0.column) },
        macroSpecs: macros,
        failureHandler: { Issue.record(Comment(rawValue: $0.message), sourceLocation: sourceLocation) }
    )
}

struct DiagnosticsMacroTests {
    @Test("a number is used by one code only")
    func duplicateNumber() {
        expectErrors("""
            @Diagnostics
            enum E {
                @Code(1, error: "a")
                case a
                @Code(1, error: "b")
                case b
            }
            """, expanded: """
            enum E {
                case a
                case b
            }
            """, [(.duplicateNumber(1), line: 5, column: 11)])
    }

    @Test("a message names each of its case's values, and only those")
    func placeholders() {
        expectErrors("""
            @Diagnostics
            enum E {
                @Code(1, error: "'{nmae}' isn't declared")
                case notDeclared(name: String)
            }
            """, expanded: """
            enum E {
                case notDeclared(name: String)
            }
            """, [(.unknownPlaceholder("nmae"), line: 3, column: 21), (.unusedValue("name"), line: 3, column: 21)])
    }

    @Test("every case has one code, and every value a label for its message to name it")
    func caseShape() {
        expectErrors("""
            @Diagnostics
            enum E {
                case bare
                @Code(1, error: "{0}")
                case unlabeled(String)
                @Code(2, error: "x")
                case first, second
            }
            """, expanded: """
            enum E {
                case bare
                case unlabeled(String)
                case first, second
            }
            """, [
                (.caseWithoutCode("bare"), line: 3, column: 5),
                (.unlabeledValue("unlabeled"), line: 5, column: 20),
                (.oneCasePerCode, line: 7, column: 5),
            ])
    }

    @Test("a code's number is an integer literal, and its message a string literal without interpolation")
    func literals() {
        expectErrors(#"""
            @Diagnostics
            enum E {
                @Code(n, error: "a")
                case a
                @Code(2, error: "\(x)")
                case b
            }
            """#, expanded: """
            enum E {
                case a
                case b
            }
            """, [(.numberNotLiteral, line: 3, column: 11), (.messageNotPlain, line: 5, column: 21)])
    }

    @Test("only an enum lists codes")
    func notAnEnum() {
        expectErrors("""
            @Diagnostics
            struct S {}
            """, expanded: """
            struct S {}
            """, [(.notAnEnum, line: 1, column: 1)])
    }
}
