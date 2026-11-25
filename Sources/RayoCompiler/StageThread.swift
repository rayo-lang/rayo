#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#elseif canImport(WinSDK)
import WinSDK
#endif
import RayoSyntax

/// The thread a compile runs its stages on, whose stack is large enough for every stage to recurse through an
/// expression as deep as the parser lets one nest.
enum StageThread {
    /// The bytes of stack the thread reserves. A debug build's stages take up to about 20 KiB of it for each level of
    /// an expression, so it reserves 64 KiB a level.
    static let stackSize = Parser.expressionLevelLimit * (64 << 10)

    /// Runs `body` on a new stage thread, and gives its result once the thread ends; or nil where no thread starts.
    static func run<Result>(_ body: () -> Result) -> Result? {
        var result: Result?
        let ran = withoutActuallyEscaping({ result = body() }) { work in runOnNewThread(work) }
        return ran ? result : nil
    }

    /// Runs `work` on a new thread whose stack reserves `stackSize` bytes, and waits for the thread to end. Returns
    /// whether the thread started.
    private static func runOnNewThread(_ work: @escaping () -> Void) -> Bool {
        var work = work
        // Each system reserves the stack's pages and commits only those the thread reaches, so a compile's memory
        // grows only with how deep it recurses.
        return withUnsafeMutablePointer(to: &work) { context in
            #if canImport(WinSDK)
            // The flag has Windows reserve the stack's size, where without it Windows would commit all of it.
            let flags = DWORD(STACK_SIZE_PARAM_IS_A_RESERVATION)
            let start: LPTHREAD_START_ROUTINE = { context in
                StageThread.runWork(at: context)
                return 0
            }
            guard let thread = CreateThread(nil, SIZE_T(stackSize), start, context, flags, nil) else { return false }
            WaitForSingleObject(thread, INFINITE)
            CloseHandle(thread)
            return true
            #else
            var attributes = pthread_attr_t()
            pthread_attr_init(&attributes)
            defer { pthread_attr_destroy(&attributes) }
            guard pthread_attr_setstacksize(&attributes, stackSize) == 0 else { return false }

            // Glibc's thread is a number; Darwin's and Musl's is a pointer, which is set once the thread starts.
            #if canImport(Glibc)
            var thread = pthread_t()
            let code = pthread_create(&thread, &attributes, { StageThread.runWork(at: $0); return nil }, context)
            guard code == 0 else { return false }
            #else
            var started: pthread_t?
            let code = pthread_create(&started, &attributes, { StageThread.runWork(at: $0); return nil }, context)
            guard code == 0, let thread = started else { return false }
            #endif
            pthread_join(thread, nil)
            return true
            #endif
        }
    }

    /// Runs the work at `context`, which `runOnNewThread` passes the thread it starts.
    private static func runWork(at context: UnsafeMutableRawPointer?) {
        context?.assumingMemoryBound(to: (() -> Void).self).pointee()
    }
}
