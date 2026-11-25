/// The proof that code runs on the stage thread, the one thread whose stack is large enough for every stage to
/// recurse through an expression as deep as the parser lets one nest. Each stage's entry point takes one, and only
/// `run(_:)` makes one, so a client reaches the stages only through `run(_:)`.
package struct StageThread: ~Copyable {
    /// The bytes of stack the stage thread reserves, 625 MiB, which bounds how deep the parser lets an expression nest:
    /// 64 KiB for each of 10,000 levels.
    package static let stackSize = 625 << 20

    private init() {}

    /// Runs `body` on the stage thread and gives its result once it ends, or nil where the thread can't start, and
    /// throws what `body` throws. Work handed over from several threads runs one piece at a time, in the order it
    /// arrives.
    package static func run<Value, Failure: Error>(
        _ body: (borrowing StageThread) throws(Failure) -> Value,
    ) throws(Failure) -> Value? {
        // Work handed over on the stage thread itself runs in place, since the thread would otherwise wait on itself.
        if StageWorker.isCurrentThread { return try body(StageThread()) }

        // The outcome crosses back from the stage thread, and the error, if any, is thrown on the client's.
        var outcome: Result<Value, Failure>?
        let work = { outcome = Result { () throws(Failure) in try body(StageThread()) } }
        guard withoutActuallyEscaping(work, do: StageWorker.run), let outcome else { return nil }
        return try outcome.get()
    }
}

/// A stage thread can't be sent to another thread, so Swift's concurrency checking reports a closure that captures
/// one and may run elsewhere, such as on a pool of threads.
@available(*, unavailable)
extension StageThread: Sendable {}
