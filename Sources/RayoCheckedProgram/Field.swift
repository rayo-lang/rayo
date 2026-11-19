/// A stored field of a struct.
public struct Field: Equatable, Sendable {
    /// The keyword that declares a field, which says whether an assignment may change it.
    public enum Kind: String, Sendable {
        /// A field an assignment may change.
        case `var`
        /// A field no assignment can change.
        case `let`
    }

    public var name: String
    public var kind: Kind
    public var type: RayoType

    public init(name: String, kind: Kind, type: RayoType) {
        self.name = name
        self.kind = kind
        self.type = type
    }
}
