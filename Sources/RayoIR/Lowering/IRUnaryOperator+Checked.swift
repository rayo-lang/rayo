import RayoSema

extension IRUnaryOperator {
    /// The IR operator that the checked `op` lowers to, whose arithmetic checks overflow.
    init(_ op: CheckedUnaryOperator) {
        self = switch op {
        case .negate: .negate(.checked)
        case .not: .not
        }
    }
}
