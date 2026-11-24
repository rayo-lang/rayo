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

    /// Reports `value`, written without a mark, where `recipient` can't take it so: where it borrows the value, and
    /// where an owning parameter needs `consume` or `copy` before a place.
    func reportUnmarked(_ value: CheckedExpr, to recipient: Recipient?) {
        switch recipient {
        case .parameter(let parameter)? where parameter.convention == .borrowed:
            reportUnlendable(value, to: parameter)
        case .parameter(let parameter)? where parameter.convention == .owned && !parameter.movesBarePlaces:
            reportUnmarkedOwned(value, to: parameter)
        case .declaration(.refLet)?:
            reportUnreferenced(value)
        default:
            break
        }
    }

    /// Reports a place given bare to a parameter that owns its argument, where the place's type isn't implicitly
    /// copyable, so nothing written says whether the call copies the value or moves it.
    private func reportUnmarkedOwned(_ value: CheckedExpr, to parameter: ArgumentParameter) {
        // A value that stands here is no `if`, since each branch of an `if` stands in its place on its own.
        guard !value.type.isImplicitlyCopyable, let handed = value.handedPlaces.first else { return }

        // The error names the marks that fit: `consume` where the code may move out of the place, `copy`, and `&`
        // where a function of the callee's name that the arguments fit borrows the argument.
        let marks = PlaceMarks(file.spelling(of: handed.place.range), mayMove: mayMove(outOf: handed),
                               mayLend: parameter.isBorrowedByOverload)
        let code = ErrorCode.unmarkedOwnedArgument(name: parameter.callee, type: typeName(of: value.type), marks: marks)
        file.errors.report(code, at: handed.place.range)
    }

    /// What a statement writes before `value`, which no code uses, to drop it. `_ =` takes a place in a local bare
    /// only where its type is implicitly copyable, so any other such place is dropped with `consume` where the code
    /// may move the value out of it, and with `copy` where it can't. Any other value is dropped as it stands.
    func dropSpelling(of value: CheckedExpr) -> DropSpelling {
        guard case .place(let place) = value.kind, let local = place.local, !value.type.isImplicitlyCopyable else {
            return .plain
        }
        return mayMove(outOf: HandedPlace(local: local, place: place)) ? .consume : .copy
    }

    /// Whether code may move the value out of `handed`.
    private func mayMove(outOf handed: HandedPlace) -> Bool {
        let liesInElement = handed.place.steps.contains {
            if case .element = $0 { true } else { false }
        }
        return MoveSource(local: names[handed.local].kind, liesInElement: liesInElement).allowsMove
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
    /// nothing written says whether the call copies the place's value or moves it, and one that borrows it for change
    /// reports it as a place written without its `mutable`.
    private func lent(_ lent: LentPlace, to parameter: ArgumentParameter, _ expected: Expectation) -> CheckedExpr? {
        switch parameter.convention {
        case .borrowed:
            heldPlace(of: lent, fitting: expected)
        case .owned:
            refused(.referenceToOwnedParameter(name: parameter.callee, type: typeName(of: expected.type)),
                    at: lent.range)
        case .mutable:
            typeFitted(lent.placeExpression, to: expected).flatMap { unmarkedLend(of: $0, to: parameter) }
        }
    }

    /// Reports `value`, written without a `mutable`, as the argument of `parameter`, which borrows its argument for
    /// change, and returns nil in its place. A place rooted in a local is reported with the `mutable` to write.
    func unmarkedLend(of value: CheckedExpr, to parameter: ArgumentParameter) -> CheckedExpr? {
        let (code, range): (ErrorCode, SourceRange) = switch value.kind {
        case .place(let place) where place.local != nil:
            (.unmarkedMutableLend(name: parameter.callee, type: spelling(of: parameter, value.type),
                                  place: file.spelling(of: place.range)), value.range)
        // Any other value is a temporary, or lies in one, so changing it would do nothing, since it dies with its
        // statement.
        case .place(let place):
            (.assignToTemporary(temporary: file.spelling(of: place.root.range)), place.root.range)
        default:
            (.assignToTemporary(temporary: file.spelling(of: value.range)), value.range)
        }
        return refused(code, at: range)
    }

    /// The type of `parameter`, which takes a value of `type`, as an error names it: after the reference the
    /// parameter takes, such as `mutable &Enemy`.
    private func spelling(of parameter: ArgumentParameter, _ type: RayoType) -> String {
        parameter.convention.reference + "\(typeName(of: type))"
    }

    /// `lent`, a `mutable` of a place, where a position expects what `expected` names. A parameter that borrows its
    /// argument for change, and a `ref var`, take the place. Any other parameter reports the `mutable` with the type
    /// it takes, and any other position reports it as unsupported.
    func mutablyLent(_ lent: MutablyLentPlace, to expected: Expectation) -> CheckedExpr? {
        switch expected.recipient {
        case .parameter(let parameter)? where parameter.convention == .mutable:
            typeFitted(lent.placeExpression, to: expected)
        // The `ref var` itself is reported as unsupported, so its place reports nothing more.
        case .declaration(.refVar)?:
            typeFitted(lent.placeExpression, to: expected)
        case .parameter(let parameter)?:
            refused(.mutableToNonMutableParameter(name: parameter.callee, type: spelling(of: parameter, expected.type)),
                    at: lent.range)
        default:
            refused(.unsupportedMutableReference, at: lent.range)
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
