/// One parameter of a function the program declares: the label a call writes before its argument, how the function
/// takes the argument, and the argument's type.
public struct FunctionParameter: Equatable, Sendable, CustomStringConvertible {
    /// The label an argument for it is written with, or nil where it is written with none.
    public var label: String?
    public var convention: ParameterConvention
    public var type: RayoType

    public init(label: String?, convention: ParameterConvention, type: RayoType) {
        self.label = label
        self.convention = convention
        self.type = type
    }

    /// The parameter as a declaration writes it, with `_` for no label, such as `by: &Int`.
    public var description: String {
        "\(label ?? "_"): \(convention.spelling(of: type))"
    }
}
