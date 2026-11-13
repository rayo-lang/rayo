import RayoIR
import RayoSema

/// The types of the places in one function: each local's, and each part's inside it.
struct PlaceTypes {
    let body: IRBody
    let types: TypeTable

    /// The fields of the struct at `place`. Lowering steps into a field only of a struct, so the place must hold one.
    func fields(ofStructAt place: Place) -> [Field] {
        // Step from the local's type into each part's in turn.
        var type = body.locals[place.root.index].type
        for step in place.steps {
            switch step {
            // A field has the type its struct declares it with.
            case .field(let index): type = fields(of: type)[index].type
            }
        }
        return fields(of: type)
    }

    /// The name of `place` as the source writes it, such as `e.stats.hp`, or nil where its local is a temporary.
    func sourceName(of place: Place) -> String? {
        // A temporary has no name in the source.
        guard case .source(let name, _, _) = body.locals[place.root.index] else { return nil }

        // Each field takes its name from the struct that holds it.
        let stepNames = place.steps.indices.map { depth in
            switch place.steps[depth] {
            case .field(let index): fields(ofStructAt: place.prefix(depth))[index].name
            }
        }
        return ([name] + stepNames).joined(separator: ".")
    }

    /// The fields of `type`, which must be a struct.
    private func fields(of type: RayoType) -> [Field] {
        // Only a struct has fields, and lowering steps into nothing else.
        guard case .structure(let id) = type else { preconditionFailure("only a struct holds fields") }
        return types[id].fields
    }
}
