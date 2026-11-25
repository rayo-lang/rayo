internal import Dispatch
import Synchronization

/// The stage thread, which starts when a client first hands it work and then lives as long as the process, and the
/// work handed to it that it hasn't begun. It runs that work one piece at a time, oldest first.
enum StageWorker {
    /// The work handed to the stage thread that it hasn't begun, oldest first.
    private static let waiting = Mutex<[Job]>([])
    /// Counts the pieces of work in `waiting`, so that the thread sleeps while there are none.
    private static let arrivals = DispatchSemaphore(value: 0)
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

        let job = Job(work: work)
        waiting.withLock { $0.append(job) }
        arrivals.signal()
        job.finished.wait()
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
        while true {
            arrivals.wait()
            runOldestJob().signal()
        }
    }

    /// Runs the oldest piece of work waiting, and gives the semaphore its client waits on. The job is dropped by the
    /// time this returns, since its work mustn't outlive the client's wait.
    private static func runOldestJob() -> DispatchSemaphore {
        let job = waiting.withLock { $0.removeFirst() }
        job.work()
        return job.finished
    }
}

/// A piece of work a client hands the stage thread, and the semaphore the client waits on until it has run. The
/// client waits through the whole run, so what the work captures is only ever used by one thread at a time.
private struct Job: @unchecked Sendable {
    let work: () -> Void
    let finished = DispatchSemaphore(value: 0)
}
