import LLVM
import RayoLLVMTestSupport

/// A module run in this process, whose functions LLVM compiles when they are first looked up, with a call to the
/// runtime's `rayo.panic` ending the call that reached it instead of the process.
struct InProcessJIT: ~Copyable {
    /// What a call came to: the value it returned, or the message of the panic that ended it.
    enum Call {
        case returned(Int64)
        case panicked(String)
    }

    private let jit: JIT

    /// Takes `module`, which leaves `rayo.panic` undefined.
    init(running module: consuming Module) throws(LLVMError) {
        // `rayo.panic` is the stand-in that ends a call with its message.
        let jit = try JIT()
        try jit.define("rayo.panic", at: UnsafeRawPointer(bitPattern: UInt(rayo_test_panic_address()))!)
        try jit.add(module)
        self.jit = jit
    }

    /// Runs the function `name`, of type `(i64, i64) -> i64`, on `left` and `right`.
    func call(_ name: String, _ left: Int64, _ right: Int64) throws(LLVMError) -> Call {
        // Compile the function, and call it where a panic ends the call.
        let function = unsafeBitCast(try jit.address(of: name), to: (@convention(c) (Int64, Int64) -> Int64).self)
        let outcome = rayo_call_catching_panic(function, left, right)

        // A call that returned comes to its value.
        guard outcome.panicked else { return .returned(outcome.value) }

        // A panic's message lives in the JIT's memory, so it is copied out while the JIT still holds it.
        let message = UnsafeRawBufferPointer(start: outcome.message, count: Int(outcome.length))
        return .panicked(String(decoding: message, as: UTF8.self))
    }
}
