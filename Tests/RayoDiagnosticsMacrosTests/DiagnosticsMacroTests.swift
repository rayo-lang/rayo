import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing
@testable import RayoDiagnosticsMacros

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
    assertMacroExpansion(source, expandedSource: expanded, diagnostics: errors, macroSpecs: macros,
                         failureHandler: { Issue.record(Comment(rawValue: $0.message), sourceLocation: sourceLocation) })
}

/// The members a table written wrong still gets, so that only the table's own errors are reported.
private let placeholderMembers = """
        var number: Int {
            0
        }

        var message: String {
            ""
        }

        var severity: Severity {
            .error
        }

        var labels: [Label: String] {
            [:]
        }

        enum Label: Sendable, Hashable {
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

            \(placeholderMembers)
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

            \(placeholderMembers)
            }
            """, reporting: [error(.unknownPlaceholder("nmae"), 3, 21), error(.unusedValue("name"), 4, 22)])
    }

    @Test func `a placeholder that reads a property names one of its case's values too`() {
        expect("""
            @Diagnostics
            enum E {
                @Code(1, error: "'{name}' has {nmae.count} letters")
                case letters(name: String)
            }
            """, expandsTo: """
            enum E {
                case letters(name: String)

            \(placeholderMembers)
            }
            """, reporting: [error(.unknownPlaceholder("nmae"), 3, 21)])
    }

    @Test("every case has one code, and every value a label for its message to name it, before its placeholders are checked")
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

            \(placeholderMembers)
            }
            """, reporting: [
                error(.caseWithoutCode("bare"), 3, 5),
                error(.unlabeledValue("unlabeled"), 5, 20),
                error(.unlabeledValue("wildcard"), 7, 19),
                error(.oneCasePerCode, 9, 5),
                error(.oneCodePerCase, 10, 26),
            ])
    }

    @Test("a code's number is a positive integer literal, and its message a one-line string literal without interpolation")
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

            \#(placeholderMembers)
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

            \(placeholderMembers)
            }
            """, reporting: [error(.conditionalCase, 5, 5)])
    }

    @Test func `a code is an error or a warning, as its '@Code' says`() {
        expect("""
            @Diagnostics
            enum E {
                @Code(1, error: "a")
                case a
                @Code(2, warning: "b")
                case b
            }
            """, expandsTo: """
            enum E {
                case a
                case b

                var number: Int {
                    switch self {
                    case .a:
                        1
                    case .b:
                        2
                    }
                }

                var message: String {
                    switch self {
                    case .a:
                        "a"
                    case .b:
                        "b"
                    }
                }

                var severity: Severity {
                    switch self {
                    case .a:
                        .error
                    case .b:
                        .warning
                    }
                }

                var labels: [Label: String] {
                    [:]
                }

                enum Label: Sendable, Hashable {
                }
            }
            """, reporting: [])
    }

    @Test func `a code's labels each give their text, which may name the code's values, under a kind of their own`() {
        expect("""
            @Diagnostics
            enum E {
                @Code(1, error: "'{name}' was moved", labels: ["moved": "'{name}' moved here", "seen": "seen"])
                case moved(name: String)
                @Code(2, warning: "{a} and {b}", labels: ["seen": "{b} seen here"])
                case pair(a: Int, b: Int)
                @Code(3, error: "c")
                case c
            }
            """, expandsTo: """
            enum E {
                case moved(name: String)
                case pair(a: Int, b: Int)
                case c

                var number: Int {
                    switch self {
                    case .moved:
                        1
                    case .pair:
                        2
                    case .c:
                        3
                    }
                }

                var message: String {
                    switch self {
                    case .moved(let v0):
                        "'\\(v0)' was moved"
                    case .pair(let v0, let v1):
                        "\\(v0) and \\(v1)"
                    case .c:
                        "c"
                    }
                }

                var severity: Severity {
                    switch self {
                    case .moved:
                        .error
                    case .pair:
                        .warning
                    case .c:
                        .error
                    }
                }

                var labels: [Label: String] {
                    switch self {
                    case .moved(let v0):
                        [.moved: "'\\(v0)' moved here", .seen: "seen"]
                    case .pair(_, let v1):
                        [.seen: "\\(v1) seen here"]
                    default:
                        [:]
                    }
                }

                enum Label: Sendable, Hashable {
                    case moved
                    case seen
                }
            }
            """, reporting: [])
    }

    @Test func `a code's labels are a dictionary from identifiers to one-line strings that name only its values`() {
        expect("""
            @Diagnostics
            enum E {
                @Code(1, error: "a", labels: ["moved": "x", "moved": "again", "not a name": "x", "seen": "\\(x)"])
                case a
                @Code(2, error: "b", labels: labels)
                case b
                @Code(3, error: "{name}", labels: ["moved": "{nmae}"])
                case c(name: Int)
            }
            """, expandsTo: """
            enum E {
                case a
                case b
                case c(name: Int)

            \(placeholderMembers)
            }
            """, reporting: [
                error(.labelTwice("moved"), 3, 49),
                error(.labelNameNotIdentifier, 3, 67),
                error(.labelNotPlain, 3, 94),
                error(.labelsNotLiteral, 5, 34),
                error(.unknownPlaceholder("nmae"), 7, 49),
            ])
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

                var severity: Severity {
                    .error
                }

                var labels: [Label: String] {
                    [:]
                }

                enum Label: Sendable, Hashable {
                }
            }
            """, reporting: [error(.memberTaken("number"), 6, 5)])
    }

    @Test func `an enum can't declare a type named 'Label', which '@Diagnostics' generates`() {
        expect("""
            @Diagnostics
            enum E {
                @Code(1, error: "a")
                case a
                struct Label {}
            }
            """, expandsTo: """
            enum E {
                case a
                struct Label {}

                var number: Int {
                    0
                }

                var message: String {
                    ""
                }

                var severity: Severity {
                    .error
                }

                var labels: [Label: String] {
                    [:]
                }
            }
            """, reporting: [error(.memberTaken("Label"), 5, 5)])
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
