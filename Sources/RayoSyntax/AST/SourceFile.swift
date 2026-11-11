public struct SourceFile: Sendable {
    public var functions: [FuncDecl]
    public var structs: [StructDecl]

    public init(functions: [FuncDecl], structs: [StructDecl]) {
        self.functions = functions
        self.structs = structs
    }
}
