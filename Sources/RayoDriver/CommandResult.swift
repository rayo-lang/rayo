/// What a `rayo` command gives: its exit code, and what it writes to its standard output and error.
public struct CommandResult: Equatable, Sendable {
    public var exitCode: Int32
    public var output: String
    public var errors: String

    public init(exitCode: Int32, output: String, errors: String) {
        self.exitCode = exitCode
        self.output = output
        self.errors = errors
    }
}
