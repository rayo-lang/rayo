import RayoDiagnostics

/// The codes of the errors and warnings that checking `source` reports.
func errors(_ source: String) -> [ErrorCode] {
    diagnostics(source).map(\.code)
}

/// The source text each of `diagnostics` covers in `source`.
func coveredText(_ diagnostics: [Diagnostic], in source: String) -> [String] {
    let bytes = Array(source.utf8)
    return diagnostics.map { String(decoding: bytes[$0.range.start.offset..<$0.range.end.offset], as: UTF8.self) }
}

/// The errors and warnings that parsing `source` and checking its syntax tree report, in source order.
func diagnostics(_ source: String) -> [Diagnostic] {
    // A stage thread that can't start has already failed the test, and leaves no errors.
    guard let checked = try? checking(source) else { return [] }
    return (checked.syntaxErrors + checked.checkErrors).inSourceOrder
}

/// The errors and warnings that `body`, as `main`'s body, reports, each as its position, code and message.
func errorLines(inMain body: String) -> [String] {
    diagnostics(mainSource(body)).map(\.description)
}

/// The errors and warnings that `body`, as `main`'s body beside `declarations`, reports, each as its position, code
/// and message.
func errorLines(inMain body: String, beside declarations: String) -> [String] {
    diagnostics("\(mainSource(body))\n\(declarations)").map(\.description)
}

/// The codes of the errors and warnings that `body`, as `main`'s body, reports, and the text of the source each
/// covers.
func codesAndCoverage(inMain body: String) -> (codes: [ErrorCode], covered: [String]) {
    let source = mainSource(body)
    let reported = diagnostics(source)
    return (reported.map(\.code), coveredText(reported, in: source))
}

/// The source of a program whose `main` runs `body`.
func mainSource(_ body: String) -> String {
    "func main() {\n\(body)\n}"
}
