import RayoCheckedProgram
import RayoDiagnostics
import RayoSema
import RayoStageThread
import RayoSyntax
import Testing

/// The syntax tree the parser makes of `source`, on the stage thread, and the errors it reports.
func parsed(_ source: String) throws -> (file: SourceFile, diagnostics: [Diagnostic]) {
    try #require(StageThread.run { thread in Parser.parse(source, on: thread) })
}

/// The errors the parser reports in `source`, and what checking its syntax tree gives, both on the stage thread. The
/// checker takes the tree as the parser leaves it, with what failed to parse marked, as the pipeline gives it.
func checking(_ source: String) throws -> (
    syntaxErrors: [Diagnostic], program: CheckedProgram, checkErrors: [Diagnostic], mainMayHaveFailed: Bool,
) {
    try #require(StageThread.run { thread in
        let (file, syntaxErrors) = Parser.parse(source, on: thread)
        let (program, checkErrors, mainMayHaveFailed) = Checker.check(file, on: thread)
        return (syntaxErrors, program, checkErrors, mainMayHaveFailed)
    })
}
