#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#elseif canImport(WinSDK)
import WinSDK
#endif

#if canImport(WinSDK)
/// The operating system's lock, which a condition variable can release while a thread waits on it.
typealias SystemLock = SRWLOCK
/// The operating system's condition variable, which wakes the threads that wait on it.
typealias SystemCondition = CONDITION_VARIABLE
#else
/// The operating system's lock, which a condition variable can release while a thread waits on it.
typealias SystemLock = pthread_mutex_t
/// The operating system's condition variable, which wakes the threads that wait on it.
typealias SystemCondition = pthread_cond_t
#endif

/// The operating system's side of the queue: its lock, and the condition variable its threads wait on.
extension StageQueue {
    /// Readies the lock and the condition for use.
    func initializeLockAndCondition() {
        #if canImport(WinSDK)
        InitializeSRWLock(lock)
        InitializeConditionVariable(condition)
        #else
        pthread_mutex_init(lock, nil)
        pthread_cond_init(condition, nil)
        #endif
    }

    /// Releases what the system holds for the lock and the condition, once no thread uses them.
    func destroyLockAndCondition() {
        // Windows holds nothing for either.
        #if !canImport(WinSDK)
        pthread_cond_destroy(condition)
        pthread_mutex_destroy(lock)
        #endif
    }

    /// Runs `body` while holding the lock, and gives what it gives.
    func withLock<Result>(_ body: () -> Result) -> Result {
        #if canImport(WinSDK)
        AcquireSRWLockExclusive(lock)
        defer { ReleaseSRWLockExclusive(lock) }
        #else
        pthread_mutex_lock(lock)
        defer { pthread_mutex_unlock(lock) }
        #endif
        return body()
    }

    /// Releases the lock until another thread wakes this one, and takes it again. A thread may also wake for no
    /// reason, so each caller tests again what it waits for.
    func waitForChange() {
        #if canImport(WinSDK)
        SleepConditionVariableSRW(condition, lock, INFINITE, 0)
        #else
        pthread_cond_wait(condition, lock)
        #endif
    }

    /// Wakes every thread that waits for a change, once the lock is free.
    func wakeAll() {
        #if canImport(WinSDK)
        WakeAllConditionVariable(condition)
        #else
        pthread_cond_broadcast(condition)
        #endif
    }
}
