import RayoSource

/// A local of a checked body, or one of its function's parameters.
public struct CheckedLocal: Sendable {
    public var name: String
    public var type: RayoType
    public var kind: LocalKind
    /// Where the source declares the local's name.
    public var range: SourceRange

    package init(name: String, type: RayoType, kind: LocalKind, range: SourceRange) {
        self.name = name
        self.type = type
        self.kind = kind
        self.range = range
    }
}
