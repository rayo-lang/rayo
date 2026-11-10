import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing
@testable import RayoDiagnosticsMacros

/// The macros under test, by the names their attributes are written with.
private let macros = [
    "Diagnostics": MacroSpec(type: DiagnosticsMacro.self),
    "Code": MacroSpec(type: CodeMacro.self),
]

/// An error the expansion must report at `line` and `column`, with `notes`.
private func error(_ error: CodeTableError, _ line: Int, _ column: Int,
                   notes: [(CodeTableNote, line: Int, column: Int)] = []) -> DiagnosticSpec {
    DiagnosticSpec(message: error.message, line: line, column: column,
                   notes: notes.map { NoteSpec(message: $0.0.message, line: $0.line, column: $0.column) })
}

/// Expands `source`, which must report `errors` and expand to `expanded`.
private func expect(_ source: String, expandsTo expanded: String, reporting errors: [DiagnosticSpec],
                    sourceLocation: SourceLocation = #_sourceLocation) {
    assertMacroExpansion(source, expandedSource: expanded, diagnostics: errors, macroSpecs: macros) { failure in
        Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
    }
}

/// The members a table written wrong still gets, so that only the table's own errors are reported.
private let fallbackMembers = """
        var number: Int {
            0
        }

        var message: String {
            ""
        }
    """

struct DiagnosticsMacroTests {
    @Test("a number is used by one code only")
    func duplicateNumber() {
        expect("""
            @Diagnostics
            enum E {
                @Code(1, error: "a")
                case a
                @Code(1, error: "b")
                case b
            }
            """, expandsTo: """
            enum E {
                case a
                case b

            \(fallbackMembers)
            }
            """, reporting: [error(.duplicateNumber(1), 5, 11, notes: [(.firstUse(1), line: 3, column: 11)])])
    }

    @Test("a message names each of its case's values, and only those")
    func placeholders() {
        expect("""
            @Diagnostics
            enum E {
                @Code(1, error: "'{nmae}' isn't declared, nor is '{nmae}'")
                case notDeclared(name: String)
            }
            """, expandsTo: """
            enum E {
                case notDeclared(name: String)

            \(fallbackMembers)
            }
            """, reporting: [error(.unknownPlaceholder("nmae"), 3, 21), error(.unusedValue("name"), 4, 22)])
    }

    @Test("every case has one code, and each value a label the message can name it by, before placeholders are checked")
    func caseShape() {
        expect("""
            @Diagnostics
            enum E {
                case bare
                @Code(1, error: "{nmae}")
                case unlabeled(String)
                @Code(2, error: "x")
                case wildcard(_ name: String)
                @Code(3, error: "x")
                case first, second
                @Code(4, error: "x") @Code(5, error: "y")
                case twice
            }
            """, expandsTo: """
            enum E {
                case bare
                case unlabeled(String)
                case wildcard(_ name: String)
                case first, second

                case twice

            \(fallbackMembers)
            }
            """, reporting: [
                error(.caseWithoutCode("bare"), 3, 5),
                error(.unlabeledValue("unlabeled"), 5, 20),
                error(.unlabeledValue("wildcard"), 7, 19),
                error(.oneCasePerCode, 9, 5),
                error(.oneCodePerCase, 10, 26),
            ])
    }

    @Test("a code's number is a positive integer literal, and its message a one-line string without interpolation")
    func literals() {
        expect(#"""
            @Diagnostics
            enum E {
                @Code(n, error: "a")
                case a
                @Code(-2, error: "b")
                case b
                @Code(0, error: "c")
                case c
                @Code(4, error: "\(x)")
                case d
                @Code(5, error: #"e"#)
                case e
                @Code(6, error: """
                    f
                    """)
                case f
            }
            """#, expandsTo: #"""
            enum E {
                case a
                case b
                case c
                case d
                case e
                case f

            \#(fallbackMembers)
            }
            """#, reporting: [
                error(.numberNotLiteral, 3, 11), error(.numberNotLiteral, 5, 11), error(.numberNotLiteral, 7, 11),
                error(.messageNotPlain, 9, 21), error(.messageNotPlain, 11, 21), error(.messageNotPlain, 13, 21),
            ])
    }

    @Test("a case under '#if' can't have a code, since every case needs one")
    func conditionalCase() {
        expect("""
            @Diagnostics
            enum E {
                #if DEBUG
                @Code(1, error: "a")
                case a
                #endif
            }
            """, expandsTo: """
            enum E {
                #if DEBUG
                case a
                #endif

            \(fallbackMembers)
            }
            """, reporting: [error(.conditionalCase, 5, 5)])
    }

    @Test("an enum can't declare what '@Diagnostics' generates")
    func memberTaken() {
        expect("""
            @Diagnostics
            enum E {
                @Code(1, error: "a")
                case a
                static var message: String { "" }
                var number: Int { 1 }
            }
            """, expandsTo: """
            enum E {
                case a
                static var message: String { "" }
                var number: Int { 1 }

                var message: String {
                    ""
                }
            }
            """, reporting: [error(.memberTaken("number"), 6, 5)])
    }

    @Test("'@Code' gives a code only to a case of a '@Diagnostics' enum")
    func codeOutsideTable() {
        expect("""
            @Code(1, error: "a")
            func f() {}
            enum E {
                @Code(2, error: "b")
                case b
            }
            """, expandsTo: """
            func f() {}
            enum E {
                case b
            }
            """, reporting: [error(.codeOutsideTable, 1, 1), error(.codeOutsideTable, 4, 5)])
    }

    @Test("only an enum lists codes")
    func notAnEnum() {
        expect("""
            @Diagnostics
            struct S {}
            """, expandsTo: """
            struct S {}
            """, reporting: [error(.notAnEnum, 1, 1)])
    }
}
