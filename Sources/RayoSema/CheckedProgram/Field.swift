/// A stored field of a struct.
public struct Field: Equatable, Sendable {
    public var name: String
    public var type: RayoType

    public init(name: String, type: RayoType) {
        self.name = name
        self.type = type
    }
}
