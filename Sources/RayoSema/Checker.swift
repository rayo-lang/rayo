import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Resolves the names and checks the types of a parsed file.
public enum Checker {
    /// Checks `file`, and returns the checked program when it has no errors.
    public static func check(_ file: SourceFile) -> (program: CheckedProgram?, diagnostics: [Diagnostic]) {
        var checker = FileChecker()
        let program = checker.check(file)
        return (checker.errors.list.isEmpty ? program : nil, checker.errors.inSourceOrder)
    }
}

private struct FileChecker {
    var errors = Diagnostics()
    let declarations = Declarations()

    mutating func check(_ file: SourceFile) -> CheckedProgram? {
        var main: FuncDecl?
        for function in file.functions {
            if function.name != "main" {
                errors.error("a program's only function is 'main'", at: function.nameRange)
            } else if main != nil {
                errors.error("'main' is declared more than once", at: function.nameRange)
                _ = check(main: function)
            } else {
                main = function
            }
        }
        guard let main else {
            let start = SourceLocation(line: 1, column: 1, offset: 0)
            errors.error("the program has no 'main' function", at: SourceRange(start, start))
            return nil
        }
        return CheckedProgram(main: check(main: main))
    }

    mutating func check(main: FuncDecl) -> CheckedFunction {
        checkSignature(ofMain: main)
        var body = BodyChecker(declarations: declarations, errors: errors)
        let statements = body.check(main.body)
        errors = body.errors
        return CheckedFunction(locals: body.locals, body: statements)
    }

    mutating func checkSignature(ofMain main: FuncDecl) {
        if let result = main.result, let type = declarations.resolve(result, reporting: &errors), type != .void {
            errors.error("'main' returns Void", at: result.range)
        }
    }
}
