import RayoSyntax

extension CheckedBinaryOperator {
    /// The checked operator that the source's `op` means.
    init(_ op: BinaryOperator) {
        self = switch op {
        case .add: .add
        case .subtract: .subtract
        case .multiply: .multiply
        case .divide: .divide
        case .remainder: .remainder
        case .equal: .equal
        case .notEqual: .notEqual
        case .less: .less
        case .lessEqual: .lessEqual
        case .greater: .greater
        case .greaterEqual: .greaterEqual
        case .and: .and
        case .or: .or
        }
    }
}
