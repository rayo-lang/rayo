public import RayoSource

/// `label name: convention Type = default`, where all but the name and the type are optional.
public struct Param: Sendable {
    /// The label a call writes before the argument, or nil for `_`. A parameter declared without a label takes
    /// its name as its label, unless the name is `_`.
    public var label: String?
    public var name: String
    public var nameRange: SourceRange
    /// The reference the parameter's type is written as, or nil where the parameter owns its argument.
    public var convention: ParamConvention?
    /// The type of the argument, or of the place a reference parameter refers to.
    public var type: TypeExpr
    /// The value a call that leaves the argument out passes.
    public var defaultValue: Expr?
    public var range: SourceRange

    /// The parameter's type as the source writes it, after its reference where it has one, such as `&Enemy`.
    public var spelledType: String {
        (convention?.rawValue ?? "") + type.spelling
    }
}
