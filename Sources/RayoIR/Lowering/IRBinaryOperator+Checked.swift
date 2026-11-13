import RayoSema

extension IRBinaryOperator {
    /// The IR operator that the checked `op` lowers to, whose arithmetic checks overflow. `op` is neither `&&` nor
    /// `||`, which lower to branches.
    init(_ op: CheckedBinaryOperator) {
        self = switch op {
        case .add: .add(.checked)
        case .subtract: .subtract(.checked)
        case .multiply: .multiply(.checked)
        case .divide: .divide(.checked)
        case .remainder: .remainder
        case .equal: .equal
        case .notEqual: .notEqual
        case .less: .less
        case .lessEqual: .lessEqual
        case .greater: .greater
        case .greaterEqual: .greaterEqual
        case .and: preconditionFailure("'&&' lowers to branches")
        case .or: preconditionFailure("'||' lowers to branches")
        }
    }
}
