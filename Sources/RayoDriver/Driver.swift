import RayoSyntax

public enum Driver {
    public struct Result: Equatable, Sendable {
        public var exitCode: Int32
        public var output: String
        public var errors: String

        public init(exitCode: Int32, output: String, errors: String) {
            self.exitCode = exitCode
            self.output = output
            self.errors = errors
        }
    }

    static let usage = """
        usage: rayoc <command> <file>

        commands:
          parse    parse the file and print its syntax tree

        """

    /// Runs `rayoc` with `arguments`, which exclude the program's name, reading source files through
    /// `readFile`, which returns nil for a file it can't read.
    public static func run(_ arguments: [String], readFile: (String) -> String?) -> Result {
        guard arguments.count == 2, arguments[0] == "parse" else {
            return Result(exitCode: 2, output: "", errors: usage)
        }
        let path = arguments[1]
        guard let source = readFile(path) else {
            return Result(exitCode: 1, output: "", errors: "rayoc: can't read '\(path)'\n")
        }
        let (file, diagnostics) = Parser.parse(source)
        if !diagnostics.isEmpty {
            return Result(exitCode: 1, output: "", errors: diagnostics.map { "\(path):\($0)\n" }.joined())
        }
        return Result(exitCode: 0, output: file.dump + "\n", errors: "")
    }
}
