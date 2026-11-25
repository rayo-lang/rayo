import RayoDiagnostics

/// A part of the code that takes a value, which decides what happens to a place that the source writes there bare.
package enum Position: Sendable {
    /// A call's argument, given to the parameter.
    case argument(ArgumentParameter)
    /// The value of a `let` or a `var`, which owns it. The keyword is the one that starts the declaration.
    case ownerDeclaration(keyword: String)
    /// The value of a `ref let`, which refers to a place.
    case referenceDeclaration
    /// The value of a `ref var`, which refers to a place that may change through it.
    case mutableReferenceDeclaration
    /// The value of a declaration of `_`, which declares no local, so nothing takes the value.
    case unnamedDeclaration
    /// The right side of `=`.
    case assignment
    /// The value that `_ =` drops.
    case drop
    /// The operand of `return`, or the value of a body that is one expression.
    case returned
    /// An element of an array literal.
    case arrayElement
    /// The value of an expression statement, which no code uses.
    case statement
    /// A value that is only read where it stands: an operand, a condition, an index, the value of a compound
    /// assignment, or the value a place starts from.
    case operand

    /// What the position does with `place`, written bare there, and the error it reports where the source must write
    /// a mark before the place.
    package func taking(_ place: GivenPlace) -> PlaceTaking {
        let taking = takingFromLocal(place)
        // A part of a temporary, such as `makeEnemy().pos`, is a value that dies with its statement, so no mark is
        // written before it, and the position reports what `takingValue` says of a value no local holds.
        guard place.source.local != nil else { return PlaceTaking(use: taking.use) }
        return taking
    }

    /// What the position does with a value that no local holds, such as a call's result or a part of one, which lies
    /// in the temporary that `temporary` spells as the source writes it.
    package func takingValue(heldBy temporary: () -> String) -> ValueTaking {
        switch self {
        case .argument(let parameter):
            parameter.takingValue(heldBy: temporary)
        // A `ref let` refers to a place, and the value has none to refer to.
        case .referenceDeclaration:
            .takes(reporting: .referenceToValue)
        case .ownerDeclaration, .mutableReferenceDeclaration, .unnamedDeclaration, .assignment, .drop, .returned,
             .arrayElement, .statement, .operand:
            .takes(reporting: nil)
        }
    }

    /// What the position does with `place`, and the error it reports, as it does where a local holds the place.
    private func takingFromLocal(_ place: GivenPlace) -> PlaceTaking {
        switch self {
        case .argument(let parameter):
            parameter.taking(place)
        case .ownerDeclaration(let keyword):
            place.owned { .ownerBorrowsPlace(keyword: keyword, place: $0.place) }
        case .referenceDeclaration:
            place.referenced
        // A `ref var` is reported as unsupported, so the place it refers to reports nothing more.
        case .mutableReferenceDeclaration:
            PlaceTaking(use: .borrow)
        case .assignment, .drop:
            place.owned { .assignmentBorrowsPlace(marks: $0) }
        case .returned, .arrayElement:
            place.copied(or: .move)
        // These only read the value: a declaration of `_` is reported, and declares no local to take it, so it reports
        // nothing of the place.
        case .unnamedDeclaration, .statement, .operand:
            place.copied(or: .lend)
        }
    }
}

/// The parameter a call's argument is given to, as a position.
package struct ArgumentParameter: Sendable {
    /// The name the call writes for what it calls, such as `show`, `Enemy` or `.init`, for an error to name it by.
    package var callee: String
    package var convention: ParameterConvention
    package var kind: ParameterKind
    /// Whether a bare value that no local holds may be lent to the parameter as a temporary.
    package var borrowsTemporaries: Bool
    /// Whether a function of the callee's name, among those whose labels and types the call's arguments fit, borrows
    /// the argument, so that a `&` of it reaches that function.
    package var isBorrowedByOverload: Bool

    package init(callee: String, convention: ParameterConvention, kind: ParameterKind, borrowsTemporaries: Bool,
                 isBorrowedByOverload: Bool) {
        self.callee = callee
        self.convention = convention
        self.kind = kind
        self.borrowsTemporaries = borrowsTemporaries
        self.isBorrowedByOverload = isBorrowedByOverload
    }

    /// What the parameter does with `place`, and the error it reports, as it does where a local holds the place.
    fileprivate func taking(_ place: GivenPlace) -> PlaceTaking {
        switch (convention, kind) {
        // A borrowing parameter is lent the place, whatever its type.
        case (.borrowed, _):
            PlaceTaking(use: .lend)
        // Every lend for change is written with `mutable`, so the parameter takes no place without it.
        case (.mutable, _):
            PlaceTaking(use: nil, error: PlaceError(unmarkedLendForChange(of: place)))
        // An owning parameter of a function takes a place with `consume` or `copy`, which say what the call does
        // with it, and `&` reaches another function of the name that borrows it.
        case (.owned, .function):
            place.owned(lendable: isBorrowedByOverload) {
                .unmarkedOwnedArgument(name: callee, type: place.typeName(), marks: $0)
            }
        // A struct's primary initializer takes the place's value as its field's.
        case (.owned, .field):
            place.copied(or: .move)
        // `.init(repeating:)` reads the value, and copies it into each element.
        case (.owned, .repeatedElement):
            place.copied(or: .lend)
        }
    }

    /// What the parameter does with a value that no local holds, which lies in the temporary `temporary` spells.
    fileprivate func takingValue(heldBy temporary: () -> String) -> ValueTaking {
        switch convention {
        // Changing a temporary would do nothing, since it dies with its statement.
        case .mutable: .refused(.assignToTemporary(temporary: temporary()))
        // A temporary is lent only to a parameter that borrows temporaries, as a built-in's does.
        case .borrowed: .takes(reporting: borrowsTemporaries ? nil : .unsupportedLentValue)
        case .owned: .takes(reporting: nil)
        }
    }

    /// The error at `place`, given bare to the parameter, which borrows it for change, naming the `mutable` to write.
    private func unmarkedLendForChange(of place: GivenPlace) -> ErrorCode {
        let type = convention.reference + "\(place.typeName())"
        return .unmarkedMutableLend(name: callee, type: type, place: place.spelling())
    }
}

private extension GivenPlace {
    /// The place as a `ref let` takes it, which reports the `&` the source must write before it. The `ref let` refers
    /// to the place all the same, so the error leaves the body its meaning; a copy of an implicitly copyable value
    /// would be a value, which no `ref let` refers to.
    var referenced: PlaceTaking {
        PlaceTaking(use: .borrow, error: PlaceError(.unreferencedPlace(place: spelling()), keepsMeaning: true))
    }

    /// A copy of the place's value where its type is implicitly copyable, and `use` of the place where it isn't.
    func copied(or use: PlaceUse) -> PlaceTaking {
        PlaceTaking(use: type.isImplicitlyCopyable ? .copy : use)
    }

    /// The place as a position takes it that owns what it takes: a copy of its value where its type is implicitly
    /// copyable, and otherwise the error `code` gives for the marks that fit, since nothing written says whether to
    /// copy the value or move it. `&` fits where the flag says lending the place reaches a function that borrows it.
    func owned(lendable: Bool = false, as code: (PlaceMarks) -> ErrorCode) -> PlaceTaking {
        guard !type.isImplicitlyCopyable else { return PlaceTaking(use: .copy) }
        let marks = PlaceMarks(spelling(), mayMove: source.allowsMove, mayLend: lendable)
        return PlaceTaking(use: .move, error: PlaceError(code(marks)))
    }
}
