import LLVM

/// How a call passes the argument of one of a function's parameters, and the attributes that tell LLVM what holds of
/// the pointer it passes, where it passes one.
enum ParameterPassing: Equatable {
    /// Split into its scalars, each an LLVM parameter of its own.
    case direct([Scalar])
    /// As a pointer to the caller's place, which the callee reads and writes as the parameter's own.
    case callerPlace([Attribute])
    /// As a pointer to a slot the caller fills and gives up, which the callee then owns as the parameter's place.
    case filledSlot([Attribute])

    /// The attributes of each LLVM parameter that passes the argument.
    var llvmParameterAttributes: [[Attribute]] {
        switch self {
        case .direct(let scalars): Array(repeating: [], count: scalars.count)
        case .callerPlace(let attributes), .filledSlot(let attributes): [attributes]
        }
    }
}
