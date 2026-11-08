import SwiftDiagnostics

/// A way in which a `@Diagnostics` enum, or a `@Code` on one of its cases, is written wrong.
enum CodeTableError: DiagnosticMessage, Equatable {
    case notAnEnum
    case caseWithoutCode(String)
    case oneCasePerCode
    case unlabeledValue(String)
    case numberNotLiteral
    case messageNotPlain
    case duplicateNumber(Int)
    case unknownPlaceholder(String)
    case unusedValue(String)

    var message: String {
        switch self {
        case .notAnEnum: "only an enum lists diagnostic codes"
        case .caseWithoutCode(let name): "case '\(name)' needs a '@Code'"
        case .oneCasePerCode: "a '@Code' gives one case its code; declare each case on its own"
        case .unlabeledValue(let name): "each value of case '\(name)' needs a label, which its message names"
        case .numberNotLiteral: "a code's number is an integer literal"
        case .messageNotPlain: "a code's message is a plain string literal, with '{label}' for a value"
        case .duplicateNumber(let number): "another code already has the number \(number)"
        case .unknownPlaceholder(let label): "the case has no value labeled '\(label)'"
        case .unusedValue(let label): "the message never names the value '\(label)'"
        }
    }

    var diagnosticID: MessageID { MessageID(domain: "RayoDiagnosticsMacros", id: "\(self)") }

    var severity: DiagnosticSeverity { .error }
}
