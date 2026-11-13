import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks what declares a local: a parameter, or a binding of a `let` or `var` with its type annotation and value.
struct BindingChecker {
    /// What a binding's type annotation and value give the local it declares.
    private enum Declared {
        /// The local's type, which the source gives at `typeRange`, and its first value, if the binding gives one.
        case typed(RayoType, typeRange: SourceRange, value: CheckedExpr?)
        /// Neither an annotation nor a value, so nothing gives the local a type.
        case untyped
        /// An annotation or a value that failed, which was reported there.
        case failed

        /// What `annotation` gives the local of a binding without a value.
        init(_ annotation: Annotation) {
            switch annotation {
            case .absent: self = .untyped
            case .resolved(let type, let range): self = .typed(type, typeRange: range, value: nil)
            case .failed: self = .failed
            }
        }

        var value: CheckedExpr? {
            // Only a typed binding gives its local a first value.
            guard case .typed(_, _, let value) = self else { return nil }
            return value
        }
    }

    /// What a binding's type annotation says of the local's type.
    private enum Annotation {
        case absent
        /// The type the annotation names, and where the source writes it.
        case resolved(RayoType, range: SourceRange)
        /// An annotation that names no type, which was reported there.
        case failed

        /// What the annotation expects of the binding's value: the type it names, where it names one.
        var expected: Expectation? {
            // An absent annotation expects nothing, and nor does one that failed.
            guard case .resolved(let type, _) = self else { return nil }
            return Expectation(type)
        }
    }

    let expressions: ExpressionChecker

    private var names: NameScopes { expressions.names }
    private var errors: ErrorList { expressions.file.errors }

    /// Declares `parameters`, whose types are `types`, as the function's first locals, in order.
    func declare(_ parameters: [Param], types: [RayoType?]) {
        for (parameter, type) in zip(parameters, types) {
            // A parameter named `_` is reported, and declares no local.
            guard bindsName(parameter.name, at: parameter.nameRange) else { continue }
            _ = names.declare(parameter.name, type: type, kind: .parameter, at: parameter.nameRange)
        }
    }

    /// Checks `binding`, which declares a local.
    func check(_ binding: Binding, declaredWith kind: BindingKind) -> CheckedStmt? {
        // Checked before the name, so a declaration of `_` still reports its type's and its value's errors.
        let declared = checkTypeAndValue(of: binding)
        // A binding of `_` is reported, and declares no local.
        guard bindsName(binding.name, at: binding.nameRange) else { return nil }
        let type = checkLocalType(declared, of: binding)
        let local = names.declare(binding.name, type: type, kind: LocalKind(kind), at: binding.nameRange)
        return local.map { .binding($0, at: binding.nameRange, declared.value) }
    }

    /// Checks `binding`'s type annotation and value, and the value against the annotation when it has both.
    private func checkTypeAndValue(of binding: Binding) -> Declared {
        let annotation = resolveAnnotation(of: binding)
        // Without a value, the annotation alone gives the local's type.
        guard let valueExpr = binding.value else { return Declared(annotation) }
        // A value that failed, or that has another type than the annotation names, was reported.
        let value = expressions.check(valueExpr, as: .take, expecting: annotation.expected)
        guard let value else { return .failed }
        // So was an annotation that failed; otherwise the value has the local's type.
        if case .failed = annotation { return .failed }
        return .typed(value.type, typeRange: value.range, value: value)
    }

    /// Resolves `binding`'s type annotation, reporting it when it names no type.
    private func resolveAnnotation(of binding: Binding) -> Annotation {
        // A binding may leave its type to its value.
        guard let annotation = binding.type else { return .absent }
        // A name that names no type was reported.
        guard let type = expressions.file.declarations.resolve(annotation, reporting: errors) else { return .failed }
        return .resolved(type, range: annotation.range)
    }

    /// Checks that `declared` gives the local `binding` declares a type other than Void, reporting it when it
    /// doesn't, and returns that type.
    private func checkLocalType(_ declared: Declared, of binding: Binding) -> RayoType? {
        switch declared {
        // No local holds a Void value.
        case .typed(.void, let typeRange, _):
            errors.report(.voidLocal(type: expressions.typeName(of: .void)), at: typeRange)
            return nil

        // Any other type is the local's.
        case .typed(let type, _, _):
            return type

        // Without an annotation or a value, nothing gives the local a type.
        case .untyped:
            errors.report(.missingLocalType(name: binding.name), at: binding.nameRange)
            return nil

        // A type or a value that failed was reported.
        case .failed:
            return nil
        }
    }

    /// Whether `name` is a name to bind, reporting it when it is `_`.
    private func bindsName(_ name: String, at range: SourceRange) -> Bool {
        // Any name but `_` binds.
        guard name == "_" else { return true }
        errors.report(.underscoreDeclared, at: range)
        return false
    }
}

private extension LocalKind {
    /// The kind of local that a declaration with `kind` declares.
    init(_ kind: BindingKind) {
        switch kind {
        case .let: self = .let
        case .var: self = .var
        }
    }
}
