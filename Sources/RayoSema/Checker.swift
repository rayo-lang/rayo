import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Resolves the names and checks the types of a parsed file.
public enum Checker {
    /// Checks `file`, and returns the checked program when it has no errors.
    public static func check(_ file: SourceFile) -> (program: CheckedProgram?, diagnostics: [Diagnostic]) {
        let checker = FileChecker(file)
        let program = checker.check()
        return (checker.errors.list.isEmpty ? program : nil, checker.errors.list.inSourceOrder)
    }
}

/// Checks a file's functions, each once. A function whose body gives its result type is checked when a call
/// first needs that type, so a call may come before the function it calls.
final class FileChecker {
    let errors = ErrorList()
    private(set) var declarations = Declarations()
    private let file: SourceFile
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
    }

    func check() -> CheckedProgram? {
        let main = declareFunctions()
        let functions = signatures.indices.map { function(FunctionID(index: $0)) }
        guard let main else {
            let start = SourceLocation(line: 1, column: 1, offset: 0)
            errors.report(.noMain, at: SourceRange(start, start))
            return nil
        }
        let checked = functions.compactMap { $0 }
        return checked.count == functions.count ? CheckedProgram(functions: checked, main: main) : nil
    }

    /// The result type of a call to `signature`, at `range`, or nil when it isn't known. A body that gives the
    /// result type is checked first, and one that is being checked already makes a cycle, which is reported.
    func result(of signature: Signature, calledAt range: SourceRange) -> RayoType? {
        switch signature.result {
        case .type(let type):
            return type
        case .failed:
            return nil
        case .givenByBody(let id) where checking.contains(id):
            errors.report(.resultDependsOnItself(signature: "\(signature)"), at: range)
            return nil
        case .givenByBody(let id):
            return body(of: id).result
        }
    }

    /// Declares the file's functions, then the prelude's functions they leave free, and returns the first `main`.
    private func declareFunctions() -> FunctionID? {
        var main: FunctionID?
        for (index, function) in file.functions.enumerated() {
            let id = FunctionID(index: index)
            let parameters = function.parameters.map(parameter(from:))
            let signature = Signature(name: function.name, callee: .function(id), parameters: parameters,
                                      result: declaredResult(of: function, id))
            signatures.append(signature)
            if !declarations.declare(signature) {
                errors.report(.functionDeclaredTwice(signature: "\(signature)"), at: function.nameRange)
            } else if function.name == "main" {
                main = main ?? id
                if let first = function.parameters.first { errors.report(.mainTakesParameters, at: first.range) }
            }
        }
        declarations.declarePrelude()
        return main
    }

    /// What a call needs to know about `parameter`, reporting what in it rayoc doesn't support: every parameter
    /// is borrowed, and every argument written. A parameter of type Void gets no type, since no local holds one.
    private func parameter(from parameter: Param) -> Parameter {
        if let convention = parameter.convention {
            errors.report(.unsupportedConvention(convention: convention.rawValue), at: parameter.range)
        }
        if let defaultValue = parameter.defaultValue { errors.report(.defaultArgument, at: defaultValue.range) }
        var type = declarations.resolve(parameter.type, reporting: errors)
        if type == .void {
            errors.report(.voidParameter, at: parameter.type.range)
            type = nil
        }
        return Parameter(label: parameter.label, type: type, spelledType: parameter.type.spelling)
    }

    /// The result type that `function`, which is `id`, declares. Without '->', it is Void, unless the body is a
    /// single expression of a function other than `main`, whose type is the result type.
    private func declaredResult(of function: FuncDecl, _ id: FunctionID) -> DeclaredResult {
        let isMain = function.name == "main"
        guard let written = function.result else {
            return !isMain && function.body.singleExpression != nil ? .givenByBody(id) : .type(.void)
        }
        guard let type = declarations.resolve(written, reporting: errors) else { return .failed }
        if isMain && type != .void {
            errors.report(.mainReturnsNonVoid, at: written.range)
            return .failed
        }
        return .type(type)
    }

    /// The checked function `id`; nil when its result type isn't known.
    private func function(_ id: FunctionID) -> CheckedFunction? {
        let body = body(of: id)
        guard let result = body.result else { return nil }
        let signature = signatures[id.index]
        return CheckedFunction(name: "\(signature)", parameterCount: signature.parameters.count, result: result,
                               locals: body.locals, body: body.statements)
    }

    /// The body of the function `id`, checked when this first asks for it.
    private func body(of id: FunctionID) -> CheckedBody {
        if let body = bodies[id] { return body }
        checking.insert(id)
        let body = checkBody(of: id)
        checking.remove(id)
        bodies[id] = body
        return body
    }

    private func checkBody(of id: FunctionID) -> CheckedBody {
        let function = file.functions[id.index]
        let declared = signatures[id.index].result
        var body = BodyChecker(file: self, result: declared.type)
        body.declare(function.parameters, types: signatures[id.index].parameters.map(\.type))
        var result = declared.type
        let statements: [CheckedStmt]
        if result != .void, let value = function.body.singleExpression {
            let returned = body.returned(value)
            if case .givenByBody = declared { result = returned?.type }
            statements = returned.map { [.returnStmt($0)] } ?? []
        } else {
            statements = body.check(function.body)
            if let result, result != .void, function.body.canComplete {
                errors.report(.missingReturn(signature: "\(signatures[id.index])"), at: function.body.closingBrace)
            }
        }
        return CheckedBody(result: result, locals: body.locals, statements: statements)
    }
}
