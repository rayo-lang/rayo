import RayoDiagnostics

/// Reads the source file at a path.
struct ReadSource: CompilationStep {
    /// The bytes of the file at a path, or nil when the file can't be read.
    var readFile: (String) -> [UInt8]?

    func run(_ path: String, errors: inout [Diagnostic]) throws(CompilationError) -> [UInt8]? {
        // A file that can't be read leaves nothing to compile.
        guard let source = readFile(path) else { throw .failed("can't read '\(path)'") }
        return source
    }
}
