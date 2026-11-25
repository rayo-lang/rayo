import Foundation

/// The bytes of stack a thread of a client that isn't the compiler's own may have: 512 KiB, a secondary thread's on
/// macOS.
let smallStackSize = 512 << 10

/// Runs `body` on a new thread whose stack holds `stackSize` bytes, and gives what it gives once it ends.
func onNewThread<Result: Sendable>(stackSize: Int, _ body: @escaping @Sendable () -> Result) async -> Result {
    await withCheckedContinuation { continuation in
        let thread = Thread { continuation.resume(returning: body()) }
        thread.stackSize = stackSize
        thread.start()
    }
}
