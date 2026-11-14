public struct SourceFile: Sendable {
    public var functions: [FuncDecl]
    public var structs: [StructDecl]
    /// The declarations that failed to parse, in source order.
    public var failedDeclarations: [FailedDecl]

    public init(functions: [FuncDecl], structs: [StructDecl], failedDeclarations: [FailedDecl] = []) {
        self.functions = functions
        self.structs = structs
        self.failedDeclarations = failedDeclarations
    }
}
