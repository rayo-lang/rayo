import RayoSource

/// `struct Name(fields) {}`, where the header and the body are optional, and the body is empty.
public struct StructDecl: Sendable {
    public var name: String
    public var nameRange: SourceRange
    /// The stored fields, in the order the header declares them.
    public var fields: [FieldDecl]
}
