/// Whether a diagnostic rejects the program, or only flags code that is likely a mistake.
public enum Severity: String, Sendable, Hashable, CustomStringConvertible {
    /// The program is wrong, and doesn't compile.
    case error
    /// The code is likely a mistake but has a meaning, and the program compiles as if the warning weren't there.
    case warning

    public var description: String { rawValue }
}
