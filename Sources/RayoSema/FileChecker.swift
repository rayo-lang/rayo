import RayoCheckedProgram
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
        for case .failed(let declaration) in file.declarations where declaration.kind == .function {
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
        let types = StructChecker(errors: errors).declare(file, withIDs: typeIDs, in: &declarations)
        declarePrimaryInitializers(of: typeIDs, in: types)
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

        // A written result type that failed, naming no type, one `main` can't return or one too large for the
        // stack, was reported where it is written.
        case .failed, .tooLargeForStack:
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

    /// Declares the primary initializer of each struct among `ids` that can be laid out, whose fields `types` gives.
    /// A struct that can't be laid out has none, since no call reaches it.
    private func declarePrimaryInitializers(of ids: [TypeID?], in types: TypeTable) {
        for case .structure(let id)? in ids where !declarations.types.hasFailed(named: id.name) {
            // The initializer takes each field's value, owned and labeled by its name, and makes the struct.
            let initializer = FunctionID(index: functions.count)
            let parameters = types[id].fields.map { field in
                Parameter(FunctionParameter(label: field.name, convention: .owned, type: field.type),
                          borrowsTemporaries: false)
            }
            let signature = Signature(name: id.name, target: .callee(.function(initializer)), parameters: parameters,
                                      result: .type(.named(.structure(id))))
            functions.append(DeclaredFunction(signature: signature, kind: .primaryInitializer(id)))
            declarations.declarePrimaryInitializer(signature, of: id)
        }
    }

    /// Declares the file's functions, then the prelude's functions they and the structs leave free, and returns the
    /// first `main`.
    private func declareFunctions() -> FunctionID? {
        // Declare each function, and note the first `main` declared, which is where the program starts.
        var main: FunctionID?
        for case .function(let function) in file.declarations {
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
        let signature = Signature(name: function.name, target: .callee(.function(id)), parameters: parameters,
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

    /// Makes the signature's parameter from the one the declaration writes: a `&T` parameter borrows its argument,
    /// a `mutable &T` one borrows it for change, and a `T` one owns it. Reports what rayoc doesn't support in it: a
    /// default value, and a `mutable &T` parameter, the type Void, or a `T` parameter of a type that isn't implicitly
    /// copyable, each of which leaves the parameter without a type, so that its calls report nothing more.
    private func parameter(from parameter: Param) -> Parameter {
        // A default value is reported, since every call writes every argument.
        if let defaultValue = parameter.defaultValue { errors.report(.defaultArgument, at: defaultValue.range) }

        // Resolve the type the parameter is written with, and the convention its reference, or the lack of one, says.
        let convention: ParameterConvention = switch parameter.convention {
        case nil: .owned
        case .borrowed: .borrowed
        case .mutable: .mutable
        }
        var type = declarations.resolve(parameter.type, reporting: errors)
        // A `mutable &` parameter is reported and keeps no type, since rayoc doesn't support one.
        if convention == .mutable {
            errors.report(.unsupportedConvention(convention: ParamConvention.mutable.rawValue), at: parameter.range)
            type = nil
        }
        // So is one of type Void, since no local holds a Void value.
        if type == .void {
            let code = ErrorCode.voidParameter(name: parameter.name, type: declarations.typeName(of: .void))
            errors.report(code, at: parameter.type.range)
            type = nil
        }
        // So is one that owns a struct or an array, which rayoc doesn't support.
        if let resolved = type, convention == .owned, !resolved.isImplicitlyCopyable {
            errors.report(.unsupportedOwnedParameter(type: declarations.typeName(of: resolved)),
                          at: parameter.type.range)
            type = nil
        }
        // So is one too large for the stack, where the call's argument lies.
        if let resolved = type, !declarations.fitsOnStack(resolved, at: parameter.type.range, reporting: errors) {
            type = nil
        }
        // rayoc lends a function the program declares only a place that a local holds.
        return Parameter(label: parameter.label, convention: convention, type: type,
                         spelledType: parameter.spelledType, borrowsTemporaries: false)
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
        // A result lies on the stack of the function that calls it, so one too large for it is reported.
        guard declarations.fitsOnStack(type, at: written.range, reporting: errors) else {
            return .tooLargeForStack(type)
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

        return CheckedProgram(types: types, functions: table, bodies: bodies, main: main)
    }

    /// Whether a function that failed to parse may have been the file's `main`: one that failed before its name, or
    /// named `main`.
    var mainMayHaveFailed: Bool {
        file.declarations.contains { declaration in
            guard case .failed(let failed) = declaration else { return false }
            return failed.kind == .function && (failed.name == nil || failed.name == "main")
        }
    }

    /// The declaration of the function `id`, whose body is checked already; nil when its signature failed, or its
    /// body gives no result type, which fails it.
    private func declaration(of id: FunctionID) -> FunctionDeclaration? {
        let function = functions[id.index]
        guard !function.signature.hasFailed, let result = body(of: id).result else { return nil }
        let parameters = function.signature.parameters.compactMap(\.declared)
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
        case .primaryInitializer(let id): BodyCheck(result: .named(.structure(id)), body: nil)
        }
    }

    /// Checks the body that `function` writes, with its parameters as its first locals, as the body of the function
    /// that `signature` declares.
    private func checkBody(of function: FuncDecl, as signature: Signature) -> BodyCheck {
        // Give the body a checker of its own.
        let body = BodyChecker(file: self, parameters: function.parameters, declaredAs: signature.parameters,
                               result: signature.result.type)

        // A function not declared Void, whose body is a single expression, returns the expression's value.
        if signature.result.type != .void, let value = function.body.singleExpression {
            let returned = body.returned(value).flatMap { fittingWhereGivenByBody($0, of: signature) }
            return BodyCheck(result: bodyResult(of: signature, returning: returned),
                             body: CheckedBody(locals: body.locals, statements: body.statements(returning: returned)))
        }

        // Any other body is checked statement by statement, and a missing `return` on a path to its end is reported.
        let statements = body.check(function.body)
        reportMissingReturn(from: function, as: signature)
        return BodyCheck(result: signature.result.type, body: CheckedBody(locals: body.locals, statements: statements))
    }

    /// `returned`, the single expression the body of the function that `signature` declares returns, or nil where
    /// it gives the function's result type and is too large for the stack, which is reported.
    private func fittingWhereGivenByBody(_ returned: CheckedExpr, of signature: Signature) -> CheckedExpr? {
        // A written result type was checked where it is written.
        guard case .givenByBody = signature.result else { return returned }
        return declarations.fittingOnStack(returned, reporting: errors)
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
