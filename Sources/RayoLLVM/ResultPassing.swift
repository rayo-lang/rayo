import LLVM

/// How a function gives its result back to its caller.
enum ResultPassing: Equatable {
    /// Returned in its scalars: none as `void`, one as itself, and more as a struct of no name.
    case direct([Scalar])
    /// Written to a slot whose pointer the caller passes ahead of the arguments, with the attributes that tell LLVM
    /// what holds of the pointer.
    case slot([Attribute])
}
