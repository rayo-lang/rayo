import RayoIR
import RayoSema

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
        guard case .source(var name, _, _) = body.locals[place.root.index] else { return nil }

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

    /// The type of the value at `place`.
    private func type(of place: Place) -> RayoType {
        do {
            return try place.type(in: body, types: types)
        } catch {
            // Lowering steps only into parts its values have.
            preconditionFailure("the IR names \(error.step) of a value of type \(error.holder)")
        }
    }
}
