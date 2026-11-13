/// A function of the prelude whose code the compiler gives, in place of a body written in Rayo. Every built-in is one
/// of the cases.
public enum Builtin: CaseIterable, Hashable, Sendable {
    /// `print(_: Int)`, which writes the integer and a newline to standard output.
    case printInt
    /// `print(_: Bool)`, which writes `true` or `false` and a newline to standard output.
    case printBool

    /// Where the built-in's name lives in the prelude.
    var name: BuiltinName {
        switch self {
        case .printInt, .printBool: .function("print")
        }
    }

    /// The parameters, in order, each with the label a call passes its argument with, or nil where it passes none.
    var parameters: [(label: String?, type: RayoType)] {
        switch self {
        case .printInt: [(nil, .int)]
        case .printBool: [(nil, .bool)]
        }
    }

    public var parameterTypes: [RayoType] {
        parameters.map(\.type)
    }

    public var result: RayoType {
        switch self {
        case .printInt, .printBool: .void
        }
    }
}
