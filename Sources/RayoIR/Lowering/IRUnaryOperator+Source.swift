import RayoSyntax

extension IRUnaryOperator {
    /// The IR operator that the source's `op` lowers to, whose arithmetic checks overflow.
    init(_ op: UnaryOperator) {
        self = switch op {
        case .negate: .negate(.checked)
        case .not: .not
        }
    }
}
