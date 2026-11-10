public struct SourceFile: Sendable {
    public var functions: [FuncDecl]
    public init(functions: [FuncDecl]) { self.functions = functions }
}
