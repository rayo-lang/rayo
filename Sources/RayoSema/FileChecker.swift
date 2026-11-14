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

    /// What checking a body gave: the body, nil for a function without one, and its function's result type, which
    /// is nil when it isn't known.
    private struct BodyCheck {
        var result: RayoType?
        var body: CheckedBody?
    }

    init(_ file: SourceFile) {
        self.file = file
        declarations = Declarations(names: TopLevelNames(of: file))
        // A function that failed to parse is declared before any other, so every use of its name finds it. A type that
        // failed to parse is declared with the other types' names.
        for declaration in file.failedDeclarations where declaration.kind == .function {
            if let name = declaration.name { declarations.declareUnparsedFunction(named: name) }
        }
    }

    /// Checks every struct and function of the file, and gives its program, which holds each declaration, and the
    /// body of each function whose body isn't tainted.
    func check() -> CheckedProgram {
        // Check every struct and function; a file without a `main` is a library, checked the same. Every type's name
        // is declared before any struct's fields are checked, since a field's type may name a struct declared further
        // down the file.
        let typeIDs = TypeNameChecker(errors: errors).declare(file, in: &declarations)
        let types = StructChecker(errors: errors).declare(file.structs, withIDs: typeIDs.structs, in: &declarations)
        declarePrimaryInitializers(of: typeIDs.structs.compactMap(\.self), in: types)
        let main = declareFunctions()
        for index in functions.indices { _ = body(of: FunctionID(index: index)) }

        // Only once every body is checked is each one's taint known.
        return program(types: types, main: main)
    }

    /// The result type of a call to a function, or nil when it isn't known. A result type that depends on itself is
    /// reported at the call.
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

        // Any other body that gives the result type is checked for it, if it hasn't been yet. A body that gives none
        // failed the function's declaration, which taints the body that calls it.
        case .givenByBody(let id):
            let result = body(of: id).result
            if result == nil { errors.taints.taint() }
            return result
        }
    }

    /// Declares the primary initializer of each of `structs` that can be laid out, whose fields `types` gives. A
    /// struct that can't be laid out has none, since no call reaches it.
    private func declarePrimaryInitializers(of structs: [StructID], in types: TypeTable) {
        for id in structs where !declarations.hasFailedType(named: id.name) {
            // The initializer takes each field's value, labeled by its name, and makes the struct.
            let initializer = FunctionID(index: functions.count)
            let parameters = types[id].fields.map { field in
                Parameter(label: field.name, type: field.type, spelledType: "\(field.type)")
            }
            let signature = Signature(name: id.name, callee: .function(initializer), parameters: parameters,
                                      result: .type(.structure(id)))
            functions.append(DeclaredFunction(signature: signature, kind: .primaryInitializer(id)))
            declarations.declarePrimaryInitializer(initializer, of: id)
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

    /// Makes the signature's parameter from the one the declaration writes. Reports what rayoc doesn't support in
    /// it: a convention, a default value, and the type Void, which leaves the parameter without a type.
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

    /// The checked program of the file's functions, each of whose bodies is checked already, with `types` and
    /// `main`.
    private func program(types: TypeTable, main: FunctionID?) -> CheckedProgram {
        // Declare each function in the program's table, with its body under its ID unless it is tainted.
        var table = FunctionTable()
        var bodies: [FunctionID: CheckedBody] = [:]
        for index in functions.indices {
            let id = FunctionID(index: index)
            let declaration = declaration(of: id)
            let declared = declaration.map { table.declare($0) } ?? table.declareFailed()
            // The table numbers the functions as the checker did, so each call reaches the function it was checked
            // against.
            precondition(declared == id, "a checked function keeps its ID")
            // A function whose declaration failed has no body a later stage could use, and nor has a tainted one.
            if declaration != nil, !errors.taints.functions.contains(id) { bodies[id] = body(of: id).body }
        }

        return CheckedProgram(types: types, functions: table, bodies: bodies, main: main,
                              mainMayHaveFailed: mainMayHaveFailed)
    }

    /// Whether a function that failed to parse may have been the file's `main`: one that failed before its name, or
    /// named `main`.
    private var mainMayHaveFailed: Bool {
        file.failedDeclarations.contains { $0.kind == .function && ($0.name == nil || $0.name == "main") }
    }

    /// The declaration of the function `id`, whose body is checked already; nil when its result type or the type of
    /// one of its parameters isn't known, which fails it.
    private func declaration(of id: FunctionID) -> FunctionDeclaration? {
        let function = functions[id.index]
        let parameters = function.signature.parameters.compactMap(\.type)
        // A function whose result type or one of whose parameters' types isn't known fails.
        guard let result = body(of: id).result, parameters.count == function.signature.parameters.count else {
            return nil
        }
        return FunctionDeclaration(name: "\(function.signature)", parameters: parameters, result: result,
                                   kind: function.kind.functionKind)
    }

    /// The body of the function `id`, checked when this first asks for it.
    private func body(of id: FunctionID) -> BodyCheck {
        // A body checked already gives what it gave then.
        if let body = bodies[id] { return body }

        // Check the body, marked as being checked while it is, so a call back into it finds the cycle, and so what it
        // reports taints it.
        checking.insert(id)
        let body = errors.taints.checkingBody(of: id) { checkBody(of: id) }
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
        // A primary initializer has no body, and makes its struct.
        case .primaryInitializer(let id): BodyCheck(result: .structure(id), body: nil)
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
