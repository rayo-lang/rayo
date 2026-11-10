import SwiftDiagnostics

/// A way in which a `@Diagnostics` enum, or a `@Code` on one of its cases, is written wrong.
enum CodeTableError: DiagnosticMessage, Equatable {
    case notAnEnum
    case caseWithoutCode(String)
    case oneCasePerCode
    case oneCodePerCase
    case conditionalCase
    case unlabeledValue(String)
    case numberNotLiteral
    case messageNotPlain
    case duplicateNumber(Int)
    case unknownPlaceholder(String)
    case unusedValue(String)
    case memberTaken(String)
    case codeOutsideTable

    var message: String {
        switch self {
        case .notAnEnum: "only an enum lists diagnostic codes"
        case .caseWithoutCode(let name): "case '\(name)' needs a '@Code'"
        case .oneCasePerCode: "a '@Code' gives one case its code; declare each case on its own"
        case .oneCodePerCase: "a case has one '@Code'"
        case .conditionalCase: "a case under '#if' can't have a code, since every case of the table needs one"
        case .unlabeledValue(let name): "each value of case '\(name)' needs a label, which its message names"
        case .numberNotLiteral: "a code's number is a positive integer literal"
        case .messageNotPlain: "a code's message is a one-line string literal, with '{label}' for a value"
        case .duplicateNumber(let number): "another code already has the number \(number)"
        case .unknownPlaceholder(let label): "the case has no value labeled '\(label)'"
        case .unusedValue(let label): "the message never names the value '\(label)'"
        case .memberTaken(let name): "'@Diagnostics' generates '\(name)', which the enum declares already"
        case .codeOutsideTable: "'@Code' gives a code to a case of a '@Diagnostics' enum"
        }
    }

    /// Names the kind of error, without its values.
    var diagnosticID: MessageID {
        // A case with values reflects as a child labeled with its name; a case without is described by its name.
        let kind = Mirror(reflecting: self).children.first?.label ?? "\(self)"
        return MessageID(domain: "RayoDiagnosticsMacros", id: kind)
    }

    var severity: DiagnosticSeverity { .error }
}
