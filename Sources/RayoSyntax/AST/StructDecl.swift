public import RayoSource

/// `struct Name(fields) { members }`, where the header and the body are optional.
public struct StructDecl: Sendable {
    public var name: String
    public var nameRange: SourceRange
    /// The stored fields, in the order the header declares them.
    public var fields: [FieldDecl]
    /// The declarations in the body, in source order, those that failed to parse among them.
    public var members: [Declaration]
}
