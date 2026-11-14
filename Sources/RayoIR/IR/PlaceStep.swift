import RayoSema

/// A step from a place to a part of the value it holds. Steps into fields order as the fields' declarations do, and
/// come before steps into elements.
public enum PlaceStep: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Steps into a struct's field, by its place in its struct's declaration.
    case field(Int)
    /// Steps into an array's element at an index the IR writes, which lies below the array's count.
    case element(Int)
    /// Steps into an array's element at the index a UInt local holds, which an `index` operation that stored it
    /// checked against the array's count.
    case elementAt(LocalID)

    /// The step as an error names it, such as `field 0`, `element 2` or `element at %3`.
    public var description: String {
        switch self {
        case .field(let index): "field \(index)"
        case .element(let index): "element \(index)"
        case .elementAt(let local): "element at %\(local.index)"
        }
    }

    /// The type of the part the step leads into from a value of type `holder`, in `body`, a body of a program whose
    /// structs `types` holds. Nil where such a value has no such part: a field its struct doesn't declare, an element
    /// past an array's end, an element at an index that a local other than a UInt holds, or a part of a value of any
    /// other type.
    public func type(from holder: RayoType, in body: IRBody, types: TypeTable) -> RayoType? {
        switch (self, holder) {
        case (.field(let index), .structure(let id)):
            types[id].fields.indices.contains(index) ? types[id].fields[index].type : nil
        case (.element(let index), .array(let count, let element)):
            (0..<count).contains(index) ? element : nil
        case (.elementAt(let local), .array(_, let element)):
            body.locals[local.index].type == .uint ? element : nil
        case (.field, _), (.element, _), (.elementAt, _):
            nil
        }
    }

    /// Whether the step may lead into the same part as `other` does, from one value. Two fields are one part where
    /// they are one field, and so are two elements at indices the IR writes. An element at an index a local holds
    /// may be any element.
    func mayLeadToSamePart(as other: PlaceStep) -> Bool {
        switch (self, other) {
        case (.elementAt, .element), (.elementAt, .elementAt), (.element, .elementAt): true
        default: self == other
        }
    }
}
