import RayoSource

/// An error in a program, and where it is.
public struct Diagnostic: Sendable, Hashable, CustomStringConvertible {
    public var code: ErrorCode
    public var range: SourceRange

    public init(_ code: ErrorCode, at range: SourceRange) {
        self.code = code
        self.range = range
    }

    public var description: String { "\(range.start): error[\(code.identifier)]: \(code.message)" }
}
