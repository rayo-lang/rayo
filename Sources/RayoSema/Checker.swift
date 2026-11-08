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
        for declaration in file.declarations {
            switch declaration {
            case .structure(let structure):
                errors.unsupported("a struct", at: structure.nameRange)
            case .function(let function) where function.name != "main":
                errors.unsupported("a function other than 'main'", at: function.nameRange)
            case .function(let function) where main != nil:
                errors.error("'main' is declared more than once", at: function.nameRange)
                _ = check(main: function)
            case .function(let function):
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
        if let parameter = main.params.first { errors.error("'main' takes no parameters", at: parameter.range) }
        if let result = main.result, let type = declarations.resolve(result, reporting: &errors), type != .void {
            errors.error("'main' returns Void, Never or Int32", at: result.range)
        }
    }
}
