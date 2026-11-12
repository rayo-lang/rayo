import RayoIR
import RayoSema

/// The types of the places in one function: each local's, and each field's inside it.
struct PlaceTypes {
    let function: IRFunction
    let types: TypeTable

    /// The fields of the struct that `fields`, outermost first, lead to inside `local`. Lowering names a path of
    /// fields only through structs, so that place must hold one.
    func fields(ofStructIn local: LocalID, at fields: some Sequence<Int>) -> [Field] {
        // Step from the local's struct into each field's in turn.
        var structFields = self.fields(of: function.locals[local.index].type)
        for field in fields {
            structFields = self.fields(of: structFields[field].type)
        }
        return structFields
    }

    /// The name of the place that `fields`, outermost first, lead to inside `local`, as the source writes it, such as
    /// `e.stats.hp`, or nil where `local` is a temporary.
    func sourceName(of local: LocalID, fields: [Int]) -> String? {
        // A temporary has no name in the source.
        guard case .source(let name, _, _) = function.locals[local.index] else { return nil }

        // Each field takes its name from the struct that holds it.
        let fieldNames = fields.indices.map { depth in
            self.fields(ofStructIn: local, at: fields.prefix(depth))[fields[depth]].name
        }
        return ([name] + fieldNames).joined(separator: ".")
    }

    /// The fields of `type`, which must be a struct.
    private func fields(of type: RayoType) -> [Field] {
        // Only a struct has fields, and lowering steps into nothing else.
        guard case .structure(let id) = type else { preconditionFailure("only a struct holds fields") }
        return types[id].fields
    }
}
