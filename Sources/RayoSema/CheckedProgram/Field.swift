/// A stored field of a struct.
public struct Field: Equatable, Sendable {
    public var name: String
    /// Whether the field is a `var`, which an assignment may change, rather than a `let`, which none can.
    public var isVariable: Bool
    public var type: RayoType

    public init(name: String, isVariable: Bool, type: RayoType) {
        self.name = name
        self.isVariable = isVariable
        self.type = type
    }
}
