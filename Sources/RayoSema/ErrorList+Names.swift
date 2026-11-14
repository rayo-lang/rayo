import RayoSource

extension ErrorList {
    /// Whether `name`, which a declaration writes at `range`, names what it declares, reporting it when it is `_`,
    /// which names nothing.
    func isNaming(_ name: String, at range: SourceRange) -> Bool {
        // Any name but `_` names what it declares.
        guard name == "_" else { return true }
        report(.underscoreDeclared, at: range)
        return false
    }
}
