/// Where a built-in's name lives in the prelude.
enum BuiltinName: Hashable {
    /// A free function of the prelude, such as `print(_: Int)`.
    case function(String)
    /// An initializer of a prelude type, such as `Int(_: Float)`.
    case initializer(of: RayoType)

    /// The name a call writes to reach the built-in: an initializer's is its type's.
    var spelling: String {
        switch self {
        case .function(let name): name
        case .initializer(let type): type.description
        }
    }
}
