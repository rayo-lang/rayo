import RayoCheckedProgram
import RayoDiagnostics
import RayoSource
import RayoSyntax

extension ExpressionChecker {
    /// Reports each place rooted in a local that `value` hands its position to, with the error `code` gives for the
    /// place's name. A position that takes its value but can't borrow it, such as a `let`'s or `var`'s declaration or
    /// an assignment, has its places reported so, since nothing written says whether to copy the value or move it. A
    /// value of an implicitly copyable type is copied there, so it has none reported.
    func reportHandedPlaces(of value: CheckedExpr, as code: (String) -> ErrorCode) {
        guard !value.type.isImplicitlyCopyable else { return }
        for handed in value.handedPlaces {
            file.errors.report(code(file.spelling(of: handed.place.range)), at: handed.place.range)
        }
    }

    /// Reports `value`, written without a `&`, where `recipient` borrows it and can't take it so.
    func reportUnlent(_ value: CheckedExpr, to recipient: Recipient?) {
        switch recipient {
        case .parameter(let parameter)? where parameter.convention == .borrowed:
            reportUnlendable(value, to: parameter)
        case .declaration(.refLet)?:
            reportUnreferenced(value)
        default:
            break
        }
    }

    /// Reports a temporary given to a borrowing parameter that takes none.
    private func reportUnlendable(_ value: CheckedExpr, to parameter: ArgumentParameter) {
        // A value that stands here is no `if`, since each branch of an `if` stands in its place on its own.
        guard value.handedPlaces.isEmpty, !parameter.borrowsTemporaries else { return }
        file.errors.report(.unsupportedLentValue, at: value.range)
    }

    /// Reports `value`, given to a `ref let`, which the source writes without a `&`. A place rooted in a local is
    /// reported with the `&` to write, even where its type is implicitly copyable, since a copy is a value, and the
    /// `ref let` refers to the place; it still refers to the place, so that error leaves the body's meaning whole. Any
    /// other value, such as a literal, a copy or a call's result, has no place to refer to, so the `ref let` fails.
    private func reportUnreferenced(_ value: CheckedExpr) {
        // A value that stands here is no `if`, since each branch of an `if` stands in its place on its own.
        guard let handed = value.handedPlaces.first else {
            file.errors.report(.referenceToValue, at: value.range)
            return
        }
        let place = file.spelling(of: handed.place.range)
        file.errors.reportKeepingMeaning(.unreferencedPlace(place: place), at: handed.place.range)
    }

    /// `lent`, a `&` of a place, as it stands where a position expects what `expected` names. The argument of a
    /// parameter that borrows, and a `ref let`'s value, take the place itself, where a local holds it. Reports the `&`
    /// anywhere else.
    func lent(_ lent: LentPlace, to expected: Expectation) -> CheckedExpr? {
        switch expected.recipient {
        case .parameter(let parameter)?:
            self.lent(lent, to: parameter, expected)

        case .declaration(.refLet)?:
            heldPlace(of: lent, fitting: expected)

        // A `ref var`, which is reported as unsupported, takes any `&`, so it reports nothing more.
        case .declaration(.refVar)?:
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
    /// borrows takes the place itself, where a local holds it. One that owns its argument reports the `&`, since
    /// nothing written says whether the call copies the place's value or moves it.
    private func lent(_ lent: LentPlace, to parameter: ArgumentParameter, _ expected: Expectation) -> CheckedExpr? {
        switch parameter.convention {
        case .borrowed:
            heldPlace(of: lent, fitting: expected)
        case .owned:
            refused(.referenceToOwnedParameter(name: parameter.callee, type: typeName(of: expected.type)),
                    at: lent.range)
        // Checking leaves a `mutable &` parameter that the source writes without a type, and no built-in or
        // initializer takes its argument for change, so no argument stands where one is expected.
        case .mutable:
            preconditionFailure("no parameter that checking declares borrows its argument for change")
        }
    }

    /// `lent`, a `mutable` of a place, where a position expects what `expected` names. A `ref var` takes the place,
    /// and any other position reports the `mutable`.
    func mutablyLent(_ lent: MutablyLentPlace, to expected: Expectation) -> CheckedExpr? {
        switch expected.recipient {
        // The `ref var` itself is reported as unsupported, so its place reports nothing more.
        case .declaration(.refVar)?: typeFitted(lent.placeExpression, to: expected)
        default: refused(.unsupportedMutableReference, at: lent.range)
        }
    }

    /// The place that `lent` lends, as a value of the type `expected` names, where a local holds it. A `&` of a
    /// temporary is reported as unsupported.
    private func heldPlace(of lent: LentPlace, fitting expected: Expectation) -> CheckedExpr? {
        guard lent.place.local != nil else { return refused(.unsupportedLentValue, at: lent.range) }
        return typeFitted(lent.placeExpression, to: expected)
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
            let place = file.spelling(of: handed.place.range)
            file.errors.report(.referenceOutlivesPlace(binding: binding, place: place), at: handed.place.range)
        }
    }

    /// Reports `mutable &operand` at `range`, naming the `mutable` of its place to write, and gives nil. A `&`, at
    /// `referenceRange`, of a value that no local holds is reported as unsupported.
    func mutableOfReference(_ operand: Expr, referenceRange: SourceRange, in range: SourceRange) -> CheckedValue? {
        // A place that failed was reported.
        guard let lentPlace = place(operand, under: self) else { return nil }
        guard lentPlace.place.local != nil else {
            file.errors.report(.unsupportedLentValue, at: referenceRange)
            return nil
        }

        let placeName = file.spelling(of: lentPlace.place.range)
        file.errors.report(.mutableOfReference(place: placeName), at: range)
        return nil
    }
}
