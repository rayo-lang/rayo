import RayoSource

/// A local of a checked body, or one of its function's parameters.
public struct CheckedLocal: Sendable {
    public var name: String
    public var type: RayoType
    public var kind: LocalKind
    /// Where the source declares the local's name.
    public var range: SourceRange
}
