import Synchronization

/// The stage thread, which starts when a client first hands it work and then lives as long as the process, and the
/// queue of work it runs, one piece at a time, oldest first.
enum StageWorker {
    /// The work handed to the stage thread.
    private static let queue = StageQueue()
    /// Whether the stage thread has started.
    private static let started = Mutex(false)
    /// The stage thread's identity, as `currentThreadIdentity` gives it on that thread, or 0 before it runs.
    private static let threadIdentity = Atomic<UInt>(0)

    /// Whether the code that asks runs on the stage thread.
    static var isCurrentThread: Bool { threadIdentity.load(ordering: .acquiring) == currentThreadIdentity }

    /// Runs `work` on the stage thread, starting the thread if no client has, and waits for it to end. Returns
    /// whether the thread runs.
    static func run(_ work: @escaping () -> Void) -> Bool {
        guard startIfNeeded() else { return false }
        queue.run(work)
        return true
    }

    /// Starts the stage thread unless it has started, and returns whether it runs. A thread that couldn't start is
    /// tried again when the next client arrives.
    private static func startIfNeeded() -> Bool {
        started.withLock { started in
            if !started { started = startThread() }
            return started
        }
    }

    /// Runs each piece of work handed to the stage thread, oldest first, for as long as the process lives.
    static func runJobs() -> Never {
        threadIdentity.store(currentThreadIdentity, ordering: .releasing)
        while true { queue.runOldest() }
    }
}
