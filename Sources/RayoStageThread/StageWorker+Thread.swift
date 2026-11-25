#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#elseif canImport(WinSDK)
import WinSDK
#endif

/// The operating system's side of the stage thread: starting it, and telling it apart from other threads.
extension StageWorker {
    /// The identity of the thread that asks, which no other running thread shares and is never 0.
    static var currentThreadIdentity: UInt {
        #if canImport(WinSDK)
        UInt(GetCurrentThreadId())
        #elseif canImport(Glibc)
        // Glibc's thread is a number; Darwin's and Musl's is a pointer.
        UInt(pthread_self())
        #else
        UInt(bitPattern: pthread_self())
        #endif
    }

    /// Starts the stage thread, whose stack reserves `StageThread.stackSize` bytes, running `runWork()`, and returns
    /// whether it started. Nothing waits for it to end, since it lives as long as the process.
    static func startThread() -> Bool {
        // Each system reserves the stack's pages and commits only those the thread reaches, so a compile's memory
        // grows only with how deep it recurses.
        let stackSize = StageThread.stackSize
        #if canImport(WinSDK)
        // The flag has Windows reserve the stack's size, where without it Windows would commit all of it.
        let flags = DWORD(STACK_SIZE_PARAM_IS_A_RESERVATION)
        let start: LPTHREAD_START_ROUTINE = { _ in StageWorker.runWork() }
        guard let thread = CreateThread(nil, SIZE_T(stackSize), start, nil, flags, nil) else { return false }
        CloseHandle(thread)
        return true
        #else
        var attributes = pthread_attr_t()
        pthread_attr_init(&attributes)
        defer { pthread_attr_destroy(&attributes) }
        guard pthread_attr_setstacksize(&attributes, stackSize) == 0,
              pthread_attr_setdetachstate(&attributes, Int32(PTHREAD_CREATE_DETACHED)) == 0 else { return false }

        // Glibc's thread is a number; Darwin's and Musl's is a pointer, which is set once the thread starts.
        #if canImport(Glibc)
        var thread = pthread_t()
        #else
        var thread: pthread_t?
        #endif
        return pthread_create(&thread, &attributes, { _ in StageWorker.runWork() }, nil) == 0
        #endif
    }
}
