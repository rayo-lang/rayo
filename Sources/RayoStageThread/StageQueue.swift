/// The work handed to the stage thread that it hasn't run, oldest first, and how much it has run. A client waits on
/// the queue until its own work has run, and the stage thread waits on it until there is work.
///
/// The operating system's lock guards every property but the lock and the condition, and its condition variable
/// wakes the threads that wait. So the queue is safe to share between threads, though the compiler can't check it.
final class StageQueue: @unchecked Sendable {
    /// The work handed to the stage thread that it hasn't begun, oldest first.
    private var waiting: [() -> Void] = []
    /// How many pieces of work clients have handed over, which numbers the next one.
    private var handed = 0
    /// How many pieces of work the stage thread has run, which are the oldest that many.
    private var finished = 0
    /// The lock and the condition variable, each at the one address the system needs.
    let lock = UnsafeMutablePointer<SystemLock>.allocate(capacity: 1)
    let condition = UnsafeMutablePointer<SystemCondition>.allocate(capacity: 1)

    init() {
        initializeLockAndCondition()
    }

    deinit {
        destroyLockAndCondition()
        lock.deallocate()
        condition.deallocate()
    }

    /// Hands `work` to the stage thread, and waits until it has run.
    func run(_ work: @escaping () -> Void) {
        withLock {
            // The work's number says when it has run, since the thread runs the work in the order it arrives.
            let number = handed
            handed += 1
            waiting.append(work)
            wakeAll()

            while finished <= number { waitForChange() }
        }
    }

    /// Runs the oldest piece of work, once there is one, and tells its client that it has.
    func runOldest() {
        let work = withLock {
            while waiting.isEmpty { waitForChange() }
            return waiting.removeFirst()
        }
        work()

        // The work is dropped before its client hears it has run, since it mustn't outlive the client's wait.
        _ = consume work
        withLock {
            finished += 1
            wakeAll()
        }
    }
}
