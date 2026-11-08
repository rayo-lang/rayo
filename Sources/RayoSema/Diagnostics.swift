import RayoDiagnostics
import RayoSource

/// Collects the errors of a check.
struct Diagnostics {
    var list: [Diagnostic] = []

    mutating func error(_ message: String, at range: SourceRange) {
        list.append(.error(message, at: range))
    }

    /// The errors by where they start in the source, those at one place in the order they were found.
    var inSourceOrder: [Diagnostic] {
        list.enumerated().sorted { a, b in
            (a.element.range.start.offset, a.offset) < (b.element.range.start.offset, b.offset)
        }.map(\.element)
    }
}
