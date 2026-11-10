import SwiftDiagnostics

/// A note that points at a code's number where the number is first used.
enum CodeTableNote: NoteMessage, Equatable {
    case firstUse(Int)

    var message: String {
        switch self {
        case .firstUse(let number): "the number \(number) is first used here"
        }
    }

    var noteID: MessageID { MessageID(domain: "RayoDiagnosticsMacros", id: "firstUse") }
}
