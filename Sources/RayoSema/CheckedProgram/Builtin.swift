/// A function of the prelude whose code the compiler gives, in place of a body written in Rayo. Every built-in is one
/// of the cases.
public enum Builtin: CaseIterable, Hashable, Sendable {
    /// `print(_: Int)`, which writes the integer and a newline to standard output.
    case printInt
    /// `print(_: UInt)`, which writes the integer in decimal and a newline to standard output.
    case printUInt
    /// `print(_: Bool)`, which writes `true` or `false` and a newline to standard output.
    case printBool
    /// `Int(_: UInt)`, which gives the Int of the UInt's value. A value above `Int.max` panics where overflow checks
    /// are on, and keeps its bits, which give a negative Int, where they are off.
    case intFromUInt
    /// `UInt(_: Int)`, which gives the UInt of the Int's value. A negative value panics where overflow checks are on,
    /// and keeps its bits, which give a UInt above `Int.max`, where they are off.
    case uintFromInt

    /// Where the built-in's name lives in the prelude.
    var name: BuiltinName {
        switch self {
        case .printInt, .printUInt, .printBool: .function("print")
        case .intFromUInt: .initializer(of: .int)
        case .uintFromInt: .initializer(of: .uint)
        }
    }

    /// The parameters, in order, each with the label a call passes its argument with, or nil where it passes none.
    var parameters: [(label: String?, type: RayoType)] {
        switch self {
        case .printInt, .uintFromInt: [(nil, .int)]
        case .printUInt, .intFromUInt: [(nil, .uint)]
        case .printBool: [(nil, .bool)]
        }
    }

    public var parameterTypes: [RayoType] {
        parameters.map(\.type)
    }

    public var result: RayoType {
        switch self {
        case .printInt, .printUInt, .printBool: .void
        case .intFromUInt: .int
        case .uintFromInt: .uint
        }
    }
}
