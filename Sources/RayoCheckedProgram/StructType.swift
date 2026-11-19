/// A struct that a program declares: its name, and its stored fields in the order the declaration gives them.
public struct StructType: Equatable, Sendable {
    public var name: String
    public var fields: [Field]

    public init(name: String, fields: [Field]) {
        self.name = name
        self.fields = fields
    }
}
