import RayoCheckedProgram
import RayoIR

/// The types of the places in one function: each local's, and each part's inside it.
struct PlaceTypes {
    let body: IRBody
    let types: TypeTable

    /// The fields of the struct at `place`. Lowering steps into a field only of a struct, so the place must hold one.
    func fields(ofStructAt place: Place) -> [Field] {
        types.fields(of: type(of: place))
    }

    /// The name of `place` as the source writes it, such as `e.stats.hp` or `e.slots[0]`, or nil where its local is a
    /// temporary. A place inside an element at an index a local holds is named by the array, since the IR keeps no
    /// source for the index.
    func sourceName(of place: Place) -> String? {
        // A temporary has no name in the source.
        guard case .source(var name, _, _, _) = body.locals[place.root.index] else { return nil }

        // Each field takes its name from the struct that holds it, and each element its index, where the IR writes it.
        for depth in place.steps.indices {
            switch place.steps[depth] {
            case .field(let index): name += "." + fields(ofStructAt: place.prefix(depth))[index].name
            case .element(let index): name += "[\(index)]"
            case .elementAt: return name
            }
        }
        return name
    }

    /// The names of the fields that `place` steps into after its first `depth` steps, as the source writes them, such
    /// as `stats.hp`, or nil where it takes no step after them. Each of those steps must lead into a field, as each
    /// step after a place's innermost element does.
    func fieldPath(of place: Place, after depth: Int) -> String? {
        guard depth < place.steps.count else { return nil }
        return place.steps.indices.dropFirst(depth).map { step in
            guard case .field(let index) = place.steps[step] else {
                preconditionFailure("a field path names only fields, found \(place.steps[step])")
            }
            return fields(ofStructAt: place.prefix(step))[index].name
        }.joined(separator: ".")
    }

    /// The type of the value at `place`.
    func type(of place: Place) -> RayoType {
        do {
            return try place.type(in: body, types: types)
        } catch {
            // Lowering steps only into parts its values have.
            preconditionFailure("the IR names \(error.step) of a value of type \(error.holder)")
        }
    }
}
