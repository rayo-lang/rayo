/// A handle to an LLVM value. A constant is valid while the context that made it lives; a function, a global or an
/// instruction is valid while its module lives, and not once the module is linked into another.
public protocol ValueHandle {
    /// The value, of whatever type it is.
    var anyValue: AnyValue { get }
}
