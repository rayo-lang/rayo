import RayoCheckedProgram

extension CheckedExpr {
    /// The places rooted in a local that the value hands its position to, in source order: the value itself, where it
    /// is such a place, and otherwise those of the value each branch of an `if` ends in, since an `if` hands its
    /// position to the branch that runs. A place in a temporary's own storage is left out, since the temporary dies
    /// with its statement, and so whatever receives the value owns it.
    var handedPlaces: [HandedPlace] {
        switch kind {
        case .place(let place, _):
            place.local.map { [HandedPlace(local: $0, place: place)] } ?? []
        case .if(_, let then, let otherwise):
            [then, otherwise].flatMap { $0.value?.handedPlaces ?? [] }
        case .integerLiteral, .boolLiteral, .copy, .consume, .arrayCount, .unary, .binary, .call, .arrayLiteral,
             .filledArray:
            []
        }
    }
}
