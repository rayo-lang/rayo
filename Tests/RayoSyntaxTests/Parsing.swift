import RayoDiagnostics
import RayoStageThread
import RayoSyntax
import Testing

/// The syntax tree the parser makes of `source`, on the stage thread, and the errors it reports.
func parsed(_ source: String) throws -> (file: SourceFile, diagnostics: [Diagnostic]) {
    try #require(StageThread.run { thread in Parser.parse(source, on: thread) })
}
