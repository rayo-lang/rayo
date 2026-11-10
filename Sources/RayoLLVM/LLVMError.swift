/// A fault in `rayoc`, or in the LLVM it compiles with, that stops LLVM compiling a program: never one in the
/// program itself.
public struct LLVMError: Error {
    public var message: String
}
