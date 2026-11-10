import RayoSource

/// `label name: convention Type = default`, where all but the name and the type are optional.
public struct Param: Sendable {
    /// The label a call writes before the argument, or nil for `_`. A parameter declared without a label takes
    /// its name as its label, unless the name is `_`.
    public var label: String?
    public var name: String
    public var nameRange: SourceRange
    public var convention: ParamConvention?
    public var type: TypeExpr
    /// The value a call that leaves the argument out passes.
    public var defaultValue: Expr?
    public var range: SourceRange
}
