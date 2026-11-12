import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks a file's structs, then its functions, each once. A function whose body gives its result type is checked
/// when a call first needs that type, so a call may come before the function it calls.
final class FileChecker {
    let errors = ErrorList()
    private(set) var declarations: Declarations
    private let file: SourceFile
    /// Which kind of declaration each of the file's top-level names belongs to.
    let names: TopLevelNames
    /// The signature of each of the file's functions, indexed by `FunctionID`.
    private var signatures: [Signature] = []
    private var bodies: [FunctionID: CheckedBody] = [:]
    /// The functions whose bodies are being checked.
    private var checking: Set<FunctionID> = []

    /// What checking a body gave: its result type is nil when it isn't known.
    private struct CheckedBody {
        var result: RayoType?
        var locals: [CheckedLocal]
        var statements: [CheckedStmt]
    }

    init(_ file: SourceFile) {
        self.file = file
        names = TopLevelNames(of: file)
        declarations = Declarations(names: names)
    }

    func check() -> CheckedProgram? {
        // Check every struct and function; a file without a `main` is a library, checked the same.
        let types = StructChecker(errors: errors).declare(file.structs, among: names, in: &declarations)
        let main = declareFunctions()
        let functions = signatures.indices.map { function(FunctionID(index: $0)) }

        // The program is checked only when its structs can be laid out and each of its functions is checked.
        let checked = functions.compactMap { $0 }
        guard let types, checked.count == functions.count else { return nil }
        return CheckedProgram(types: types, functions: checked, main: main)
    }

    /// The result type of a call to `signature` at `range`, or nil when it isn't known. A result type that depends
    /// on itself is reported at `range`.
    func result(of signature: Signature, calledAt range: SourceRange) -> RayoType? {
        switch signature.result {
        // A declared result type is the call's.
        case .type(let type):
            return type

        // A written result type that failed, naming no type or one `main` can't return, was reported where it is
        // written.
        case .failed:
            return nil

        // A body being checked can't give its result type to a call inside it, directly or through other calls.
        case .givenByBody(let id) where checking.contains(id):
            errors.report(.resultDependsOnItself(signature: "\(signature)"), at: range)
            return nil

        // Any other body that gives the result type is checked for it, if it hasn't been yet.
        case .givenByBody(let id):
            return body(of: id).result
        }
    }

    /// Declares the file's functions, then the prelude's functions they and the structs leave free, and returns the
    /// first `main`.
    private func declareFunctions() -> FunctionID? {
        // Declare each function, and note the first `main` declared, which is where the program starts.
        var main: FunctionID?
        for (index, function) in file.functions.enumerated() {
            let id = FunctionID(index: index)
            let isDeclared = declare(function, as: id)
            // A function that isn't declared, or isn't a `main`, starts nothing.
            guard isDeclared, function.name == "main" else { continue }
            main = main ?? id
            // A `main` takes no parameters.
            if let first = function.parameters.first { errors.report(.mainTakesParameters, at: first.range) }
        }

        // Declare the prelude's functions that the file's structs and functions leave free.
        declarations.declarePrelude()
        return main
    }

    /// Declares `function` as `id`, and returns whether it is declared. Reports a function whose name belongs to a
    /// struct, which is still declared, and one that takes arguments as a function before it does, which isn't.
    private func declare(_ function: FuncDecl, as id: FunctionID) -> Bool {
        // Give the function its signature.
        let parameters = function.parameters.map(parameter(from:))
        let signature = Signature(name: function.name, callee: .function(id), parameters: parameters,
                                  result: declaredResult(of: function, id))
        signatures.append(signature)

        // Declare the function, reporting a name it can't take.
        let isDeclared = declarations.declare(signature)
        if names.kind(of: function.name) == .structure {
            // A function whose name belongs to a struct is reported, and still declared: a call looks up functions
            // alone, so it still finds the function, and raises no error of its own.
            errors.report(.alreadyDeclared(name: function.name), at: function.nameRange)
        } else if !isDeclared {
            // A function with the name, labels and parameter types of one before it is reported, since no call
            // could reach it.
            errors.report(.functionDeclaredTwice(signature: "\(signature)"), at: function.nameRange)
        }
        return isDeclared
    }

    /// What a call needs to know about `parameter`. Reports what in it rayoc doesn't support: a convention, a
    /// default value, and the type Void, which leaves the parameter without a type.
    private func parameter(from parameter: Param) -> Parameter {
        // A convention is reported, since every parameter borrows its argument.
        if let convention = parameter.convention {
            errors.report(.unsupportedConvention(convention: convention.rawValue), at: parameter.range)
        }
        // A default value is reported, since every call writes every argument.
        if let defaultValue = parameter.defaultValue { errors.report(.defaultArgument, at: defaultValue.range) }

        // Resolve the type the parameter is written with.
        var type = declarations.resolve(parameter.type, reporting: errors)
        // A parameter of type Void is reported and keeps no type, since no local holds a Void value.
        if type == .void {
            errors.report(.voidParameter, at: parameter.type.range)
            type = nil
        }
        return Parameter(label: parameter.label, type: type, spelledType: parameter.type.spelling)
    }

    /// The result type that `function`, which is `id`, declares, or `.givenByBody` where its body gives it.
    private func declaredResult(of function: FuncDecl, _ id: FunctionID) -> DeclaredResult {
        let isMain = function.name == "main"
        // Without `->`, a body that is a single expression gives the result type, except `main`'s; any other
        // function returns Void.
        guard let written = function.result else {
            return !isMain && function.body.singleExpression != nil ? .givenByBody(id) : .type(.void)
        }
        // A written type that names no type was reported where it is written.
        guard let type = declarations.resolve(written, reporting: errors) else { return .failed }
        // A `main` that returns a value is reported.
        if isMain && type != .void {
            errors.report(.mainReturnsNonVoid, at: written.range)
            return .failed
        }
        return .type(type)
    }

    /// The checked function `id`; nil when its result type isn't known.
    private func function(_ id: FunctionID) -> CheckedFunction? {
        let body = body(of: id)
        // A function whose result type isn't known doesn't check.
        guard let result = body.result else { return nil }
        let signature = signatures[id.index]
        return CheckedFunction(name: "\(signature)", parameterCount: signature.parameters.count, result: result,
                               locals: body.locals, body: body.statements)
    }

    /// The body of the function `id`, checked when this first asks for it.
    private func body(of id: FunctionID) -> CheckedBody {
        // A body checked already gives what it gave then.
        if let body = bodies[id] { return body }

        // Check the body, marked as being checked while it is, so a call back into it finds the cycle.
        checking.insert(id)
        let body = checkBody(of: id)
        checking.remove(id)
        bodies[id] = body
        return body
    }

    /// Checks the body of the function `id`, with its parameters as its first locals.
    private func checkBody(of id: FunctionID) -> CheckedBody {
        // Give the body a checker of its own.
        let function = file.functions[id.index]
        let signature = signatures[id.index]
        var body = BodyChecker(file: self, parameters: function.parameters, types: signature.parameters.map(\.type),
                               result: signature.result.type)

        // A function not declared Void, whose body is a single expression, returns the expression's value.
        if signature.result.type != .void, let value = function.body.singleExpression {
            let returned = body.returned(value)
            let statements: [CheckedStmt] = returned.map { [.returnStmt($0)] } ?? []
            return CheckedBody(result: bodyResult(of: signature, returning: returned), locals: body.locals,
                               statements: statements)
        }

        // Any other body is checked statement by statement, and a missing `return` on a path to its end is reported.
        let statements = body.check(function.body)
        reportMissingReturn(from: function, as: signature)
        return CheckedBody(result: signature.result.type, locals: body.locals, statements: statements)
    }

    /// The result type of the function that `signature` declares, whose body is a single expression that checks to
    /// `returned`: the declared type, or the expression's when no type is written.
    private func bodyResult(of signature: Signature, returning returned: CheckedExpr?) -> RayoType? {
        // A declared result type is the function's, whatever the expression's type.
        guard case .givenByBody = signature.result else { return signature.result.type }
        return returned?.type
    }

    /// Reports a missing `return` when a run can reach the end of `function`'s body, though the function returns a
    /// value.
    private func reportMissingReturn(from function: FuncDecl, as signature: Signature) {
        // A function that returns Void, or whose result type failed and was reported, needs no `return`; nor does a
        // body that can't run to its end.
        guard let result = signature.result.type, result != .void, function.body.canComplete else { return }
        errors.report(.missingReturn(signature: "\(signature)"), at: function.body.closingBrace)
    }
}

private extension Block {
    /// Whether a run can reach the block's end, worked out from its syntax alone, so a statement that fails to check
    /// still counts for what it does.
    var canComplete: Bool {
        statements.allSatisfy(\.canComplete)
    }

    /// Whether a `break` in the block, outside any loop nested in it, leaves the loop the block belongs to.
    var breaks: Bool {
        statements.contains { statement in
            switch statement.kind {
            // A `break` leaves the loop.
            case .breakStmt:
                return true

            // So does one in either branch of an `if`.
            case .ifStmt(_, let then, let otherwise):
                return then.breaks || otherwise?.breaks == true

            // A `break` in a nested loop leaves that loop, and no other statement leaves one.
            default:
                return false
            }
        }
    }
}

private extension Stmt {
    /// Whether a run can go on past the statement.
    var canComplete: Bool {
        switch kind {
        // A `return`, a `break` and a `continue` go elsewhere.
        case .returnStmt, .breakStmt, .continueStmt:
            return false

        // An `if` with an `else` completes when either branch does.
        case .ifStmt(_, let then, let otherwise?):
            return then.canComplete || otherwise.canComplete

        // A loop completes once its condition fails.
        case .whileStmt(let condition, let body):
            // A `while true` that no `break` leaves never completes.
            if case .boolLiteral(true) = condition.kind { return body.breaks }
            return true

        // Every other statement goes on, an `if` without an `else` among them.
        default:
            return true
        }
    }
}
