public struct SourceFile: Sendable {
    /// The file's top-level declarations, in source order, those that failed to parse among them.
    public var declarations: [Declaration]

    public init(declarations: [Declaration]) {
        self.declarations = declarations
    }
}
