/// A handle to an LLVM integer value: one whose width its Swift type fixes, or one that carries its width with it.
public protocol IntegerHandle: ValueHandle {
    /// Takes `value` as an integer this handle holds, or gives nil where it is of another type.
    init?(_ value: some ValueHandle)
}
