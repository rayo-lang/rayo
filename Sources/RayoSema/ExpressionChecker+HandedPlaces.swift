import RayoCheckedProgram
import RayoDiagnostics
import RayoSource

extension ExpressionChecker {
    /// Reports each place rooted in a local that `value` hands its position to, with the error `code` gives for the
    /// place's name. A position that takes its value but can't borrow it, such as a `let`'s or `var`'s declaration or
    /// an assignment, has its places reported so, since nothing written says whether to copy the value or move it. A
    /// value of an implicitly copyable type is copied there, so it has none reported.
    func reportHandedPlaces(of value: CheckedExpr, as code: (String) -> ErrorCode) {
        guard !value.type.isImplicitlyCopyable else { return }
        for handed in value.handedPlaces {
            file.errors.report(code(sourceName(of: handed)), at: handed.place.range)
        }
    }

    /// Reports `value`, which the source writes without a `&`, where `recipient` takes a reference: a parameter that
    /// borrows its argument, or a `ref let`. A value of any other recipient is written as it should be.
    func reportUnlent(_ value: CheckedExpr, to recipient: Recipient?) {
        switch recipient {
        case .parameter(let parameter)? where parameter.convention == .borrowed:
            reportUnlent(value, to: parameter)
        case .declaration(.refLet)?:
            reportUnreferenced(value)
        default:
            break
        }
    }

    /// Reports `value`, given to `parameter`, which borrows its argument, since a call lends such a parameter a place
    /// with `&`. A place rooted in a local is reported with the `&` to write, even where its type is implicitly
    /// copyable, since a copy is a value, and the parameter takes the place; the call still lends the place, so that
    /// error leaves the body's meaning whole. Any other value, such as a call's result or a copy, is reported as
    /// unsupported, since rayoc lends no value that no local holds.
    private func reportUnlent(_ value: CheckedExpr, to parameter: ArgumentParameter) {
        // A value that stands here is no `if`, since each branch of an `if` stands in its place on its own.
        guard let handed = value.handedPlaces.first else {
            file.errors.report(.unsupportedLentValue, at: value.range)
            return
        }
        let code = ErrorCode.unlentPlace(name: parameter.callee, type: typeName(of: value.type),
                                         place: sourceName(of: handed))
        file.errors.reportKeepingMeaning(code, at: handed.place.range)
    }

    /// Reports `value`, given to a `ref let`, where it is a place rooted in a local, with the `&` to write, even where
    /// its type is implicitly copyable, since a copy is a value, and the `ref let` refers to the place. The `ref let`
    /// still refers to the place, so the error leaves the body's meaning whole. Any other value gives the `ref let` a
    /// value of its own, which the declaration reports where no branch of it gives a place.
    private func reportUnreferenced(_ value: CheckedExpr) {
        // A value that stands here is no `if`, since each branch of an `if` stands in its place on its own.
        guard let handed = value.handedPlaces.first else { return }
        file.errors.reportKeepingMeaning(.unreferencedPlace(place: sourceName(of: handed)), at: handed.place.range)
    }

    /// `lent`, a `&` of a place, as it stands where a position expects what `expected` names. The argument of a
    /// parameter that borrows, and a `ref let`'s value, take the place itself, and check its type as they would the
    /// value's. Reports the `&` anywhere else.
    func lent(_ lent: LentPlace, to expected: Expectation) -> CheckedExpr? {
        switch expected.recipient {
        case .parameter(let parameter)?:
            self.lent(lent, to: parameter, expected)

        // A `ref var`, which is reported as unsupported, takes a `&` as a `ref let` does, so it reports nothing more.
        case .declaration(.refLet)?, .declaration(.refVar)?:
            typeFitted(lent.placeExpression, to: expected)

        // A `let` or a `var` would hold the reference as a value.
        case .declaration(let kind)?:
            refused(.unsupportedHeldReference(keyword: kind.keyword), at: lent.range)

        // No other position takes a reference.
        case nil:
            refused(.unsupportedReference, at: lent.range)
        }
    }

    /// `lent`, a `&` of a place, as the argument of `parameter`, of the type `expected` names. A parameter that
    /// borrows takes the place itself. One that owns its argument reports the `&`, since nothing written says whether
    /// the call copies the place's value or moves it.
    private func lent(_ lent: LentPlace, to parameter: ArgumentParameter, _ expected: Expectation) -> CheckedExpr? {
        switch parameter.convention {
        case .borrowed:
            typeFitted(lent.placeExpression, to: expected)
        case .owned:
            refused(.referenceToOwnedParameter(name: parameter.callee, type: typeName(of: expected.type)),
                    at: lent.range)
        // Checking leaves a `mutable &` parameter that the source writes without a type, and no built-in or
        // initializer takes its argument for change, so no argument stands where one is expected.
        case .mutable:
            preconditionFailure("no parameter that checking declares borrows its argument for change")
        }
    }

    /// `lent`, a `mutable &` of a place, as it stands where a position expects what `expected` names. A `ref var`
    /// takes the place itself, checking its type as it would the value's, and reports nothing more, since the
    /// `ref var` is reported as unsupported. Reports the `mutable &` anywhere else.
    func mutablyLent(_ lent: MutablyLentPlace, to expected: Expectation) -> CheckedExpr? {
        switch expected.recipient {
        case .declaration(.refVar)?: typeFitted(lent.placeExpression, to: expected)
        // A `ref let` is read-only, so the fix is to declare the `ref var` that the `mutable &` asks for.
        case .declaration(.refLet)?: refused(.mutableReferenceToReferenceLet, at: lent.range)
        default: refused(.unsupportedMutableReference, at: lent.range)
        }
    }

    /// Reports `code` at `range`, where a position refuses the value the source writes there, and returns nil in its
    /// place.
    private func refused(_ code: ErrorCode, at range: SourceRange) -> CheckedExpr? {
        file.errors.report(code, at: range)
        return nil
    }

    /// Reports each place that `value` hands the `ref let` called `binding` in a local out of scope here: one that a
    /// branch of an `if` declares, which ends with the branch while the `ref let` lives on.
    func reportEndedPlaces(of value: CheckedExpr, referredToBy binding: String) {
        for handed in value.handedPlaces where !names.isInScope(handed.local) {
            let place = sourceName(of: handed)
            file.errors.report(.referenceOutlivesPlace(binding: binding, place: place), at: handed.place.range)
        }
    }

    /// The name of `place` as the source writes it, such as `e.stats.hp` or `g[i][0]`, for an error to name it by.
    /// An index the source writes as anything but an integer literal or a local's bare name is written `…`, since the
    /// checked program keeps no text for it.
    private func sourceName(of place: HandedPlace) -> String {
        var name = names[place.local].name
        var type = names[place.local].type
        for step in place.place.steps {
            let part = written(step, from: type)
            name += part.text
            type = part.type
        }
        return name
    }

    /// `step` as the source writes it after the value of `type` it steps from, such as `.hp` or `[i]`, and the type
    /// of the part it leads to.
    private func written(_ step: CheckedPlaceStep, from type: RayoType) -> (text: String, type: RayoType) {
        switch (step, type) {
        // A field takes its name from the struct that holds it.
        case (.field(let index, _), .named(.structure(let id))):
            file.declarations.types.fields(of: id)[index].writtenStep
        // An element takes its index, where the source writes one that has a name.
        case (.element(let index, _, _), .array(_, let element)):
            ("[\(indexName(of: index))]", element)
        // Checking steps into a field only of a struct, and into an element only of an array.
        default:
            preconditionFailure("a place steps into a part that its value doesn't have")
        }
    }

    /// The index of an element as an error writes it: an integer literal's value, a local's bare name, or `…`.
    private func indexName(of index: CheckedExpr) -> String {
        switch index.kind {
        case .integerLiteral(let value, _): "\(value)"
        case .place(let place) where place.steps.isEmpty:
            if case .local(let local, _) = place.root { names[local].name } else { "…" }
        default: "…"
        }
    }
}

private extension Field {
    /// The step into the field as the source writes it after the struct that holds it, such as `.hp`, and the
    /// field's type.
    var writtenStep: (text: String, type: RayoType) {
        ("." + name, type)
    }
}
