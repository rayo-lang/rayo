import RayoCheckedProgram
import RayoDiagnostics
import RayoSource
import RayoSyntax

extension ExpressionChecker {
    /// `bare` as `position` takes it, with the error the position gives it reported, or nil where the position refuses
    /// it.
    func given(_ bare: BarePlace, to position: Position) -> CheckedExpr? {
        // A place in a temporary, such as `makeEnemy().pos`, is a value, which the position takes or refuses as it
        // does any other.
        if bare.place.local == nil, !takesValue(at: bare.range, inTemporaryAt: bare.place.root.range, by: position) {
            return nil
        }

        let taking = position.taking(given(bare.place, of: bare.placeType))
        if let error = taking.error { report(error, at: bare.range) }
        return taking.use.map(bare.expression)
    }

    /// `value`, which no local holds, as `position` takes it, with what the position can't take of it reported. A
    /// parameter that borrows its argument for change takes only a place lent with `mutable`, so it refuses the value,
    /// and gives nil.
    func taken(_ value: CheckedExpr, by position: Position) -> CheckedExpr? {
        takesValue(at: value.range, inTemporaryAt: value.range, by: position) ? value : nil
    }

    /// Whether `position` takes a value that no local holds, which the source writes at `range` and which lies in the
    /// temporary the source writes at `temporary`, reporting what the position can't take of it.
    private func takesValue(at range: SourceRange, inTemporaryAt temporary: SourceRange,
                            by position: Position) -> Bool {
        // Changing a temporary would do nothing, since it dies with its statement, so a parameter that borrows for
        // change refuses it.
        if case .argument(let parameter) = position, parameter.convention == .mutable {
            file.errors.report(.assignToTemporary(temporary: file.spelling(of: temporary)), at: temporary)
            return false
        }

        if let error = valueError(at: position) { file.errors.report(error, at: range) }
        return true
    }

    /// The error at a value that no local holds, given to `position`, or nil where the position takes it.
    private func valueError(at position: Position) -> ErrorCode? {
        switch position {
        // A temporary is lent only to a parameter that borrows temporaries, as a built-in's does.
        case .argument(let parameter) where parameter.convention == .borrowed && !parameter.borrowsTemporaries:
            .unsupportedLentValue
        // A `ref let` refers to a place, and the value has none to refer to.
        case .referenceDeclaration:
            .referenceToValue
        default:
            nil
        }
    }

    /// `place`, which holds a value of `type`, as a position is given it.
    private func given(_ place: CheckedPlace, of type: RayoType) -> GivenPlace {
        let liesInElement = place.steps.contains {
            if case .element = $0 { true } else { false }
        }
        let source = MoveSource(local: place.local.map { names[$0].kind }, liesInElement: liesInElement)
        return GivenPlace(type: type, source: source, spelling: { file.spelling(of: place.range) },
                          typeName: { typeName(of: type) })
    }

    /// Reports `error` at `range`, keeping the body's meaning where the error says it does.
    private func report(_ error: PlaceError, at range: SourceRange) {
        if error.keepsMeaning {
            file.errors.reportKeepingMeaning(error.code, at: range)
        } else {
            file.errors.report(error.code, at: range)
        }
    }

    /// What a statement writes before `value`, which no code uses, to drop it.
    func dropMark(of value: CheckedExpr) -> DropMark {
        // `_ =` takes a value that no place holds as it stands. An `if` that ends in places is dropped as it stands
        // too, since `consume` and `copy` take a place, and `_ =` names the mark each branch needs.
        guard case .place(let place, _) = value.kind else { return .bare }
        return given(place, of: value.type).dropMark
    }

    /// `lent`, a `&` of a place, as it stands where a position expects what `expected` names. The argument of a
    /// parameter that borrows, and a `ref let`'s value, take the place itself, where a local holds it. Reports the `&`
    /// anywhere else.
    func lent(_ lent: LentPlace, to expected: Expectation) -> CheckedExpr? {
        switch expected.position {
        case .argument(let parameter):
            self.lent(lent, to: parameter, expected)

        case .referenceDeclaration:
            heldPlace(of: lent, fitting: expected, as: .borrow)

        // A `ref var`, which is reported as unsupported, takes any `&`, so it reports nothing more.
        case .mutableReferenceDeclaration:
            typeFitted(lent.placeExpression(as: .borrow), to: expected)

        // Nor does a declaration of `_`, which is reported, and declares nothing to hold the reference.
        case .unnamedDeclaration:
            typeFitted(lent.placeExpression(as: .lend), to: expected)

        // A `let` or a `var` would hold the reference as a value.
        case .ownerDeclaration(let keyword):
            refused(.unsupportedHeldReference(keyword: keyword), at: lent.range)

        // No other position takes a reference.
        case .assignment, .drop, .returned, .arrayElement, .statement, .operand:
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
            heldPlace(of: lent, fitting: expected, as: .lend)
        case .owned:
            refused(.referenceToOwnedParameter(name: parameter.callee, type: typeName(of: expected.type)),
                    at: lent.range)
        case .mutable:
            lent.barePlace.settled(expecting: expected, by: self)
        }
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
        switch expected.position {
        case .argument(let parameter) where parameter.convention == .mutable:
            typeFitted(lent.placeExpression, to: expected)
        // The `ref var` itself is reported as unsupported, and a declaration of `_` for its name, so the place reports
        // nothing more.
        case .mutableReferenceDeclaration, .unnamedDeclaration:
            typeFitted(lent.placeExpression, to: expected)
        case .argument(let parameter):
            refused(.mutableToNonMutableParameter(name: parameter.callee, type: spelling(of: parameter, expected.type)),
                    at: lent.range)
        default:
            refused(.unsupportedMutableReference, at: lent.range)
        }
    }

    /// The place that `lent` lends, as a value of the type `expected` names that its position makes `use` of, where a
    /// local holds it. A `&` of a temporary is reported as unsupported.
    private func heldPlace(of lent: LentPlace, fitting expected: Expectation, as use: PlaceUse) -> CheckedExpr? {
        guard lent.place.local != nil else { return refused(.unsupportedLentValue, at: lent.range) }
        return typeFitted(lent.placeExpression(as: use), to: expected)
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
