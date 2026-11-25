import RayoCheckedProgram
import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks what declares a local: a parameter, or a binding of a declaration, with its type annotation and value.
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
    }

    let expressions: ExpressionChecker

    private var names: NameScopes { expressions.names }
    private var errors: ErrorList { expressions.file.errors }
    private var declarations: Declarations { expressions.file.declarations }

    /// Declares `parameters`, which `signature` declares, as the function's first locals, in order.
    func declare(_ parameters: [Param], declaredAs signature: [Parameter]) {
        for (parameter, declared) in zip(parameters, signature) {
            // A parameter named `_` is reported, and declares no local.
            guard errors.isNaming(parameter.name, at: parameter.nameRange) else { continue }
            _ = names.declare(parameter.name, type: declared.type, kind: .parameter(declared.convention),
                              at: parameter.nameRange)
        }
    }

    /// Checks `binding`, which a declaration of `kind` declares as a local.
    func check(_ binding: Binding, declaredWith kind: DeclarationKind) -> CheckedStmt? {
        // Checked before the name, so a declaration of `_` still reports its type's and its value's errors.
        let declared = checkTypeAndValue(of: binding, declaredWith: kind)

        // A binding of `_` is reported, and declares no local.
        guard errors.isNaming(binding.name, at: binding.nameRange) else { return nil }

        if let value = declared.value { checkHolding(value, in: binding, declaredWith: kind) }

        let type = checkLocalType(declared, of: binding)
        let local = names.declare(binding.name, type: type, kind: LocalKind(kind), at: binding.nameRange)
        return local.map { .binding($0, at: binding.nameRange, declared.value) }
    }

    /// Reports what `binding`, declared with `kind`, can't hold of `value`, the value it is given, beyond what the
    /// value's position reported.
    private func checkHolding(_ value: CheckedExpr, in binding: Binding, declaredWith kind: DeclarationKind) {
        switch kind {
        // A `let` or `var` owns its value, which its position took as it can.
        case .let, .var:
            break

        // A `ref let` refers to a place, which each branch of its value gives, as its position reported, and one that
        // lasts as long as the `ref let` does.
        case .refLet:
            reportEndedPlaces(of: value, referredToBy: binding.name)

        case .refVar:
            errors.report(.unsupportedReferenceVar, at: binding.nameRange)
        }
    }

    /// Reports each place that `value` hands the `ref let` called `binding` in a local out of scope here: one that a
    /// branch of an `if` declares, which ends with the branch while the `ref let` lives on.
    private func reportEndedPlaces(of value: CheckedExpr, referredToBy binding: String) {
        for handed in value.handedPlaces where !names.isInScope(handed.local) {
            let place = expressions.file.spelling(of: handed.place.range)
            errors.report(.referenceOutlivesPlace(binding: binding, place: place), at: handed.place.range)
        }
    }

    /// Checks `binding`'s type annotation and value, which a declaration of `kind` gives the local it declares, and
    /// the value against the annotation when it has both.
    private func checkTypeAndValue(of binding: Binding, declaredWith kind: DeclarationKind) -> Declared {
        let annotation = resolveAnnotation(of: binding)
        // Without a value, the annotation alone gives the local's type.
        guard let valueExpr = binding.value else { return Declared(annotation) }

        // A binding of `_` declares no local, so nothing takes its value, which reports only its own errors.
        let position: Position = binding.name == "_" ? .unnamedDeclaration : kind.valuePosition

        // A value that failed, or that has another type than the annotation names, was reported; otherwise the value
        // has the local's type, which the annotation gives where there is one.
        let value: CheckedExpr? = switch annotation {
        case .resolved(let type, _): expressions.check(valueExpr, expecting: Expectation(type, at: position))
        case .absent: expressions.check(valueExpr, at: position)
        // An annotation that failed was reported, and leaves the value no type to settle to, so the value reports
        // only the errors it has on its own, and not those the missing type would bring, such as an implicit
        // member's.
        case .failed: reportOwnErrors(of: valueExpr)
        }
        guard let value else { return .failed }
        let typeRange = if case .resolved(_, let range) = annotation { range } else { value.range }
        return .typed(value.type, typeRange: typeRange, value: value)
    }

    /// Reports the errors that `valueExpr` has on its own, and returns nil in place of the value, which no type
    /// settles.
    private func reportOwnErrors(of valueExpr: Expr) -> CheckedExpr? {
        expressions.reportSettlingErrors(of: [expressions.value(of: valueExpr)])
        return nil
    }

    /// Resolves `binding`'s type annotation, reporting it when it names no type.
    private func resolveAnnotation(of binding: Binding) -> Annotation {
        // A binding may leave its type to its value.
        guard let annotation = binding.type else { return .absent }
        // A name that names no type was reported.
        guard let type = declarations.resolve(annotation, reporting: errors) else { return .failed }
        return .resolved(type, range: annotation.range)
    }

    /// Checks that `declared` gives the local `binding` declares a type other than Void, which fits on the stack,
    /// reporting it when it doesn't, and returns that type.
    private func checkLocalType(_ declared: Declared, of binding: Binding) -> RayoType? {
        switch declared {
        // No local holds a Void value.
        case .typed(.void, let typeRange, _):
            errors.report(.voidLocal(name: binding.name, type: expressions.typeName(of: .void)), at: typeRange)
            return nil

        // Any other type is the local's, where the local fits on the stack.
        case .typed(let type, let typeRange, _):
            return declarations.fitsOnStack(type, at: typeRange, reporting: errors) ? type : nil

        // Without an annotation or a value, nothing gives the local a type.
        case .untyped:
            errors.report(.missingLocalType(name: binding.name), at: binding.nameRange)
            return nil

        // A type or a value that failed was reported.
        case .failed:
            return nil
        }
    }
}

private extension LocalKind {
    /// The kind of local that a declaration with `kind` declares. A `ref var`, which is reported as unsupported, is
    /// declared as a `ref let`, so its uses report nothing more.
    init(_ kind: DeclarationKind) {
        switch kind {
        case .let: self = .let
        case .var: self = .var
        case .refLet, .refVar: self = .refLet
        }
    }
}
