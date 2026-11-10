import Testing
import RayoDiagnostics
import RayoDriver

/// The errors `rayoc check` reports for `source`, saved as `main.rayo`.
func errors(_ source: String) -> [ErrorCode] {
    diagnostics(source).map(\.code)
}

/// The source text each of `diagnostics` covers in `source`.
func coveredText(_ diagnostics: [Diagnostic], in source: String) -> [String] {
    let bytes = Array(source.utf8)
    return diagnostics.map { String(decoding: bytes[$0.range.start.offset..<$0.range.end.offset], as: UTF8.self) }
}

/// The diagnostics `rayoc check` reports for `source`, saved as `main.rayo`.
func diagnostics(_ source: String) -> [Diagnostic] {
    let result = Driver.run(["check", "main.rayo"]) { $0 == "main.rayo" ? Array(source.utf8) : nil }
    #expect(result.exitCode == (result.diagnostics.isEmpty ? 0 : 1))
    #expect(result.output == "")
    return result.diagnostics
}

/// The errors that `body`, as `main`'s body, reports, each as its position, code and message.
func errorLines(inMain body: String) -> [String] {
    diagnostics("func main() {\n\(body)\n}").map(\.description)
}

/// The codes of the errors that `body`, as `main`'s body, reports, and the text of `main.rayo` each covers.
func codesAndCoverage(inMain body: String) -> (codes: [ErrorCode], covered: [String]) {
    let source = "func main() {\n\(body)\n}"
    let reported = diagnostics(source)
    return (reported.map(\.code), coveredText(reported, in: source))
}
