import RayoSema

/// A step from a place to a part of the value it holds. Steps into fields order as the fields' declarations do.
public enum PlaceStep: Hashable, Comparable, Sendable {
    /// Steps into a struct's field, by its place in its struct's declaration.
    case field(Int)

    /// The field the step leads into from a value of `type`, whose struct `types` holds, or nil where such a value
    /// has no such field.
    public func field(of type: RayoType, in types: TypeTable) -> Field? {
        switch self {
        case .field(let index):
            // Only a struct has fields, and only those it declares.
            guard case .structure(let id) = type else { return nil }
            let fields = types[id].fields
            return fields.indices.contains(index) ? fields[index] : nil
        }
    }
}
