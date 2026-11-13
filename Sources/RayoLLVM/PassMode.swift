import LLVM

/// How a call passes one of a function's arguments, or its result, and the attributes that tell LLVM what holds of
/// the pointer it passes, where it passes one.
enum PassMode: Equatable {
    /// Split into its scalars, each an LLVM parameter of its own. A result returns its scalars as one value: none as
    /// `void`, one as itself, and more as a struct of no name.
    case direct([Scalar])
    /// As a pointer to the caller's place, which the callee reads and writes as the parameter's own.
    case callerPlace([Attribute])
    /// As a pointer to a slot the caller fills and gives up, which the callee then owns as the parameter's place.
    case filledSlot([Attribute])
    /// A result, which the callee writes to a slot the caller passes a pointer to, ahead of the arguments.
    case resultSlot([Attribute])

    /// The attributes of the pointer the mode passes, or none where it passes the value directly.
    var attributes: [Attribute] {
        switch self {
        case .direct: []
        case .callerPlace(let attributes), .filledSlot(let attributes), .resultSlot(let attributes): attributes
        }
    }
}
