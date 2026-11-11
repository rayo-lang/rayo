/// A handle to an LLVM type, valid while the context that made the type lives.
public protocol TypeHandle {
    /// The type, of whatever kind it is.
    var anyType: AnyType { get }
}
