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
        for effect in body.blocks.flatMap(\.effects).joined() {
            switch effect {
            case .store(let destination):
                try verify(.store, of: destination.place)
            case .begin(_, let access) where access.kind == .modify:
                try verify(.modify, of: access.place)
            default:
                break
            }
        }
    }

    /// Throws where code may not make `change` to `place`, by the kind of the local it starts from.
    private func verify(_ change: PlaceChange, of place: Place) throws(IRViolation) {
        // A temporary is lowering's own, and holds whatever lowering stores in it.
        guard case .source(let name, let kind, let type, _) = body.locals[place.root.index] else { return }
        let isWhole = place.steps.isEmpty
        guard !ChangedPlace(local: kind, isWhole: isWhole).allows(change) else { return }

        // The violation says what changes the place, and names the local as the source declares it.
        let does = switch change {
        case .store: "stores to"
        case .modify: "begins a modify access to"
        }
        let changed = "\(isWhole ? "" : "part of ")%\(place.root.index)"
        let local = switch kind {
        case .let: "let '\(name)'"
        case .refLet: "ref let '\(name)'"
        case .var: "var '\(name)'"
        case .parameter(let convention): "parameter '\(name)' of \(convention.spelling(of: type))"
        }
        let message = "the IR \(does) \(changed), the \(local), which may not change so"
        throw IRViolation(function: function, message: message)
    }
}
