import RayoCheckedProgram
import RayoDiagnostics
package import RayoStageThread
import RayoSyntax

/// Resolves the names and checks the types of a parsed file.
public enum Checker {
    /// Checks `file`, and returns its checked program, which holds a body for each function whose body isn't
    /// tainted, with the errors checking found. It also says whether a function that failed to parse may have been
    /// the file's `main`: one that failed before its name, or named `main`.
    package static func check(
        _ file: SourceFile, on thread: borrowing StageThread,
    ) -> (program: CheckedProgram, diagnostics: [Diagnostic], mainMayHaveFailed: Bool) {
        let checker = FileChecker(file)
        let program = checker.check()
        return (program, checker.errors.list.inSourceOrder, checker.mainMayHaveFailed)
    }
}
