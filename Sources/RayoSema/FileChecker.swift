import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks a file's structs, then its functions, each once. A function whose body gives its result type is checked
/// when a call first needs that type, so a call may come before the function it calls.
final class FileChecker {
    let errors = ErrorList()
    private(set) var declarations: Declarations
    private let file: SourceFile
    /// The functions the checker declares, indexed by `FunctionID`.
    private var functions: [DeclaredFunction] = []
    private var bodies: [FunctionID: BodyCheck] = [:]
    /// The functions whose bodies are being checked.
    private var checking: Set<FunctionID> = []

    /// What checking a body gave: the body, and its function's result type, which is nil when it isn't known.
    private struct BodyCheck {
        var result: RayoType?
        var body: CheckedBody
    }

    /// A function of the checked program: its declaration, and its checked body.
    private typealias Definition = (declaration: FunctionDeclaration, body: CheckedBody)

    init(_ file: SourceFile) {
        self.file = file
        declarations = Declarations(names: TopLevelNames(of: file))
    }

    func check() -> CheckedProgram? {
        // Check every struct and function; a file without a `main` is a library, checked the same.
        let typeIDs = TypeNameChecker(errors: errors).declare(file, in: &declarations)
        let types = StructChecker(errors: errors).declare(file.structs, withIDs: typeIDs.structs, in: &declarations)
        let main = declareFunctions()
        let checked = functions.indices.map { checkedFunction(FunctionID(index: $0)) }

        // The program is checked only when its structs can be laid out and each of its functions is checked.
        let definitions = checked.compactMap { $0 }
        guard let types, definitions.count == checked.count else { return nil }
        return program(of: definitions, types: types, main: main)
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
        for function in file.functions {
            let (id, isDeclared) = declare(function)
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

    /// Gives `function` the next ID, and returns it and whether calls can reach the function by its name. Reports a
    /// function whose name belongs to a type, which calls still reach, and one that takes arguments as a function
    /// before it does, which they don't.
    private func declare(_ function: FuncDecl) -> (id: FunctionID, isDeclared: Bool) {
        // Give the function its ID and its signature, and add it to the checker's functions.
        let id = FunctionID(index: functions.count)
        let parameters = function.parameters.map(parameter(from:))
        let signature = Signature(name: function.name, callee: .function(id), parameters: parameters,
                                  result: declaredResult(of: function, id))
        functions.append(DeclaredFunction(signature: signature, kind: .written(function)))

        // Declare the function, reporting a name it can't take.
        let isDeclared = declarations.declare(signature)
        if declarations.kind(of: function.name) == .type {
            // A function whose name belongs to a type is reported, and still declared: a call looks up functions
            // alone, so it still finds the function, and raises no error of its own.
            errors.report(.alreadyDeclared(name: function.name), at: function.nameRange)
        } else if !isDeclared {
            // A function with the name, labels and parameter types of one before it is reported, since no call
            // could reach it.
            errors.report(.functionDeclaredTwice(signature: "\(signature)"), at: function.nameRange)
        }
        return (id, isDeclared)
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
            errors.report(.voidParameter(type: declarations.typeName(of: .void)), at: parameter.type.range)
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
            errors.report(.mainReturnsNonVoid(type: declarations.typeName(of: .void)), at: written.range)
            return .failed
        }
        return .type(type)
    }

    /// The checked program of `definitions`, which are in the order of their functions' IDs.
    private func program(of definitions: [Definition], types: TypeTable, main: FunctionID?) -> CheckedProgram {
        // Declare each function in the program's table, with its body under its ID.
        var table = FunctionTable()
        var bodies: [FunctionID: CheckedBody] = [:]
        for (index, definition) in definitions.enumerated() {
            let id = table.declare(definition.declaration)
            // The table numbers the functions as the checker did, so each call reaches the function it was checked
            // against.
            precondition(id == FunctionID(index: index), "a checked function keeps its ID")
            bodies[id] = definition.body
        }

        return CheckedProgram(types: types, functions: table, bodies: bodies, main: main)
    }

    /// The declaration and the checked body of the function `id`; nil when its result type or the type of one of its
    /// parameters isn't known.
    private func checkedFunction(_ id: FunctionID) -> Definition? {
        let check = body(of: id)
        let function = functions[id.index]
        let parameters = function.signature.parameters.compactMap(\.type)
        // A function whose result type or one of whose parameters' types isn't known doesn't check.
        guard let result = check.result, parameters.count == function.signature.parameters.count else { return nil }
        let declaration = FunctionDeclaration(name: "\(function.signature)", parameters: parameters, result: result,
                                              kind: function.kind.functionKind)
        return (declaration, check.body)
    }

    /// The body of the function `id`, checked when this first asks for it.
    private func body(of id: FunctionID) -> BodyCheck {
        // A body checked already gives what it gave then.
        if let body = bodies[id] { return body }

        // Check the body, marked as being checked while it is, so a call back into it finds the cycle.
        checking.insert(id)
        let body = checkBody(of: id)
        checking.remove(id)
        bodies[id] = body
        return body
    }

    /// Checks the body of the function `id`.
    private func checkBody(of id: FunctionID) -> BodyCheck {
        let function = functions[id.index]
        return switch function.kind {
        // A function the source writes has the body its declaration holds.
        case .written(let declaration): checkBody(of: declaration, as: function.signature)
        }
    }

    /// Checks the body that `function` writes, with its parameters as its first locals, as the body of the function
    /// that `signature` declares.
    private func checkBody(of function: FuncDecl, as signature: Signature) -> BodyCheck {
        // Give the body a checker of its own.
        let body = BodyChecker(file: self, parameters: function.parameters, types: signature.parameters.map(\.type),
                               result: signature.result.type)

        // A function not declared Void, whose body is a single expression, returns the expression's value.
        if signature.result.type != .void, let value = function.body.singleExpression {
            let returned = body.returned(value)
            let statements: [CheckedStmt] = returned.map { [.returnStmt($0)] } ?? []
            return BodyCheck(result: bodyResult(of: signature, returning: returned),
                             body: CheckedBody(locals: body.locals, statements: statements))
        }

        // Any other body is checked statement by statement, and a missing `return` on a path to its end is reported.
        let statements = body.check(function.body)
        reportMissingReturn(from: function, as: signature)
        return BodyCheck(result: signature.result.type, body: CheckedBody(locals: body.locals, statements: statements))
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
        guard let result = signature.result.type, result != .void, Reachability.canComplete(function.body) else {
            return
        }
        errors.report(.missingReturn(signature: "\(signature)"), at: function.body.closingBrace)
    }
}
