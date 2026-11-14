import RayoDiagnostics
import RayoIR
import RayoSema
import RayoSource
import RayoSyntax
import SnapshotTesting
import Testing

/// The diagnostics of a test's source that the parser or the checker rejected.
struct RejectedSource: Error {
    let diagnostics: [Diagnostic]
}

/// Parses, checks and lowers `source`, throwing a `RejectedSource` where the parser or the checker rejects it.
func lowered(_ source: String) throws(RejectedSource) -> IRProgram {
    let (file, syntaxErrors) = Parser.parse(Array(source.utf8))
    guard syntaxErrors.isEmpty else { throw RejectedSource(diagnostics: syntaxErrors) }

    let (program, checkErrors) = Checker.check(file)
    guard let program else { throw RejectedSource(diagnostics: checkErrors) }

    return Lowering.lower(program)
}

/// Lowers `source`, and expects the IR's text to be the snapshot `name.ir`, and to read back as the same IR.
func expectLowering(
    of source: String, toMatch name: String, sourceLocation: Testing.SourceLocation = #_sourceLocation,
) throws {
    let program = try lowered(source)
    let text = IRPrinter.text(of: program)
    Snapshot("\(name).ir").expect(text, sourceLocation: sourceLocation)
    #expect(try IRParser.program(from: text) == program, sourceLocation: sourceLocation)
}

/// Lowers a `main` whose body is `body`, and expects the IR's text to be the snapshot `name.ir`, and to read back as
/// the same IR.
func expectLowering(
    ofMain body: String, toMatch name: String, sourceLocation: Testing.SourceLocation = #_sourceLocation,
) throws {
    try expectLowering(of: "func main() {\n\(body)\n}", toMatch: name, sourceLocation: sourceLocation)
}

extension IRProgram {
    /// The body of the function whose ID is at `index`.
    func body(at index: Int) -> IRBody {
        // A test asks only for the body of a function its source writes, which has one.
        guard let body = bodies[FunctionID(index: index)] else { preconditionFailure("function \(index) has no body") }
        return body
    }
}
