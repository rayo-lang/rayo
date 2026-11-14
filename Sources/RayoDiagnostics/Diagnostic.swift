import RayoSource

/// An error or a warning in a program, where it is, and the other places that explain it, each under a label.
public struct Diagnostic: Sendable, Hashable, CustomStringConvertible {
    /// A place a diagnostic points to beside its own, and the label that says what happened there.
    public struct LabeledRange: Sendable, Hashable {
        public let label: ErrorCode.Label
        public let range: SourceRange

        public init(_ label: ErrorCode.Label, at range: SourceRange) {
            self.label = label
            self.range = range
        }
    }

    public let code: ErrorCode
    public let severity: Severity
    public let range: SourceRange
    /// The other places that explain the diagnostic, in the order a reader goes through them.
    public let labeledRanges: [LabeledRange]

    /// A diagnostic of `code` at `range`, with `labeledRanges`, each under a label `code` declares.
    public init(_ code: ErrorCode, at range: SourceRange, labeling labeledRanges: [LabeledRange] = []) {
        self.init(code, severity: code.severity, at: range, labeling: labeledRanges)
    }

    /// A diagnostic as `init(_:at:labeling:)` makes it, but with `severity` in place of its code's.
    init(_ code: ErrorCode, severity: Severity, at range: SourceRange, labeling labeledRanges: [LabeledRange] = []) {
        let labels = code.labels
        precondition(labeledRanges.allSatisfy { labels[$0.label] != nil }, "\(code) declares no such label")
        self.code = code
        self.severity = severity
        self.range = range
        self.labeledRanges = labeledRanges
    }

    public var description: String { "\(range.start): \(severity)[\(code.identifier)]: \(code.message)" }

    /// Each labeled place, as its position and its label's text, in order.
    public var notes: [String] {
        // The initializer checked that the code declares each label.
        let labels = code.labels
        return labeledRanges.map { "\($0.range.start): note: \(labels[$0.label]!)" }
    }
}

extension Array where Element == Diagnostic {
    /// The diagnostics by where they start in the source, those that start at one place in the order they come in.
    public var inSourceOrder: [Diagnostic] {
        enumerated().sorted { a, b in
            (a.element.range.start, a.offset) < (b.element.range.start, b.offset)
        }.map(\.element)
    }
}
