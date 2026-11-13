import LLVM

/// A function declared in the program's module, with the signature that says how a call passes its arguments and
/// takes its result.
struct DeclaredFunction {
    let function: Function
    let signature: LoweredSignature
}
