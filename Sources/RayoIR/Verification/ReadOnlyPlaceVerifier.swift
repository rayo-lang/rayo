import RayoCheckedProgram

/// Checks that one function's body changes no place code may only read, such as a place of a `&T` parameter. The
/// emitter tells LLVM that nothing writes through such a parameter, so a change of one would have undefined behaviour.
struct ReadOnlyPlaceVerifier {
    private let body: IRBody
    /// The name of the function whose body this is, which a violation names.
    private let function: String

    init(body: IRBody, of function: String) {
        self.body = body
        self.function = function
    }

    /// Throws for the first store or modify access found whose place may not change so, in the order of the blocks
    /// and of the effects in each. Every block is checked, whether or not a path reaches it.
    func verify() throws(IRViolation) {
        for block in body.blocks {
            try block.forEachEffect { effect throws(IRViolation) in try verify(effect) }
        }
    }

    /// Throws where `effect` changes a place that may not change so. Only a store and the beginning of a modify
    /// access change a place.
    private func verify(_ effect: Effect) throws(IRViolation) {
        switch effect {
        case .store(let destination):
            try verify(.store, of: destination.place)
        case .begin(_, let access) where access.kind == .modify:
            try verify(.modify, of: access.place)
        default:
            break
        }
    }

    /// Throws where code may not make `change` to `place`, by the kind of the local it starts from.
    private func verify(_ change: PlaceChange, of place: Place) throws(IRViolation) {
        // A temporary is lowering's own, and holds whatever lowering stores in it.
        guard case .source(let name, let kind, let type, _) = body.locals[place.root.index] else { return }
        let changed = ChangedPlace(local: kind, isPart: !place.steps.isEmpty)
        guard let readOnly = changed.refusal(of: change) else { return }

        let local = switch readOnly {
        case .borrowedParameter: "parameter '\(name)' of \(ParameterConvention.borrowed.spelling(of: type))"
        case .let: "let '\(name)'"
        case .refLet: "ref let '\(name)'"
        }
        throw violation(of: local, by: change, to: place)
    }

    /// The violation of a `change` to `place`, which starts from the read-only local that `local` describes.
    private func violation(of local: String, by change: PlaceChange, to place: Place) -> IRViolation {
        let action = switch change {
        case .store: "stores to"
        case .modify: "begins a modify access to"
        }
        let part = place.steps.isEmpty ? "" : "part of "
        let message = "the IR \(action) \(part)%\(place.root.index), the \(local), which may not change so"
        return IRViolation(function: function, message: message)
    }
}
