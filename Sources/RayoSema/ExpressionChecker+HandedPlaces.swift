import RayoCheckedProgram
import RayoDiagnostics

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

    /// Reports `value` where `expected` names a parameter that borrows its argument, since a call lends such a
    /// parameter a place with `&`. A place rooted in a local is reported with the `&` to write, even where its type
    /// is implicitly copyable, since a copy is a value, and the parameter takes the place; the call still lends the
    /// place, so that error leaves the body's meaning whole. Any other value, such as a call's result or a copy, has
    /// no place that the call can lend.
    func reportUnlent(_ value: CheckedExpr, to expected: Expectation) {
        guard let parameter = expected.parameter, parameter.convention == .borrowed else { return }
        // A value that stands here is no `if`, since each branch of an `if` stands in its place on its own.
        guard let handed = value.handedPlaces.first else {
            file.errors.report(.unlendableValue, at: value.range)
            return
        }
        let code = ErrorCode.unlentPlace(name: parameter.callee, type: typeName(of: value.type),
                                         place: sourceName(of: handed))
        file.errors.reportKeepingMeaning(code, at: handed.place.range)
    }

    /// `lent`, a `&` of a place, as it stands where a position expects what `expected` names. The argument of a
    /// parameter that borrows takes the place itself, and checks its type as it would the value's. Reports the `&`
    /// anywhere else.
    func lent(_ lent: LentPlace, to expected: Expectation) -> CheckedExpr? {
        // Only a call's argument takes a reference.
        guard let parameter = expected.parameter else {
            file.errors.report(.unsupportedReference, at: lent.range)
            return nil
        }

        let place = CheckedExpr(kind: .place(lent.place), type: lent.placeType, range: lent.range)
        return switch parameter.convention {
        case .borrowed: typeFitted(place, to: expected)
        case .owned: reportReference(lent, toOwning: parameter, expected)
        // Checking leaves a `mutable &` parameter that the source writes without a type, and no built-in or
        // initializer takes its argument for change, so no argument stands where one is expected.
        case .mutable: preconditionFailure("no parameter that checking declares borrows its argument for change")
        }
    }

    /// Reports `lent`, given to `parameter`, which owns its argument of the type `expected` names, and returns nil.
    /// Nothing written says whether the call copies the place's value or moves it, so the argument fails.
    private func reportReference(
        _ lent: LentPlace, toOwning parameter: ArgumentParameter, _ expected: Expectation,
    ) -> CheckedExpr? {
        file.errors.report(.referenceToOwnedParameter(name: parameter.callee, type: typeName(of: expected.type)),
                           at: lent.range)
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
