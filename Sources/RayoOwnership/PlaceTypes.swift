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
        guard case .source(let name, _, _, _) = body.locals[place.root.index] else { return nil }
        return name + writtenSteps(of: place, from: 0).text
    }

    /// The name of `place` as the source writes it from the value its first `depth` steps lead to, such as `stats.hp`
    /// or `inner[0].n`, or nil where the source can't write it so: where it starts at an element of that value, or an
    /// index a local holds leads to it.
    func partName(of place: Place, after depth: Int) -> String? {
        // A part named from the value that holds it starts with a field.
        guard depth < place.steps.count, case .field = place.steps[depth] else { return nil }
        let written = writtenSteps(of: place, from: depth)
        guard written.reachesPlace else { return nil }

        // The name starts with the field's own, without the `.` that joins it to the value that holds it.
        return String(written.text.dropFirst())
    }

    /// The steps of `place` from its step at `depth` on, as the source writes them after the value they start from,
    /// such as `.stats.hp` or `[0].n`, and whether they reach the place. They stop before an element at an index a
    /// local holds, since the IR keeps no source for the index.
    private func writtenSteps(of place: Place, from depth: Int) -> (text: String, reachesPlace: Bool) {
        var text = ""
        for step in place.steps.indices.dropFirst(depth) {
            // Each field takes its name from the struct that holds it, and each element its index, where the IR
            // writes it.
            switch place.steps[step] {
            case .field(let index): text += "." + fields(ofStructAt: place.prefix(step))[index].name
            case .element(let index): text += "[\(index)]"
            case .elementAt: return (text, false)
            }
        }
        return (text, true)
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
