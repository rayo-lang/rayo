internal import CLLVM

/// A fault in a module or in the code that builds it, which LLVM reports: never one in the program the module
/// compiles.
public struct LLVMError: Error, Equatable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

/// Returns the text of a message LLVM hands back, and disposes of the message.
package func takeMessage(_ message: UnsafeMutablePointer<CChar>?) -> String {
    // LLVM gives no message where it has nothing to say.
    guard let message else { return "" }
    defer { LLVMDisposeMessage(message) }
    return String(cString: message)
}
