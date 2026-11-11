/// A handle to an LLVM value, valid while the context that made the value lives.
public protocol ValueHandle {
    /// The value, of whatever type it is.
    var anyValue: AnyValue { get }
}
