/// Writes object code to the file at `path`.
struct WriteObject: CompilationStep {
    var path: String
    /// Writes bytes to the file at a path, and returns whether it could.
    var writeFile: (String, [UInt8]) -> Bool

    func run(_ objectCode: [UInt8]) throws(CompilationError) {
        // A file that can't be written leaves the compile without its result.
        guard writeFile(path, objectCode) else { throw .failed("can't write '\(path)'") }
    }
}
