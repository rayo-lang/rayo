import Foundation
import Synchronization
import Testing
import RayoStageThread

/// How many pieces of work are on the stage thread at once, and the most there have been.
private final class Occupancy: Sendable {
    private let current = Atomic(0)
    private let most = Atomic(0)

    var mostAtOnce: Int { most.load(ordering: .sequentiallyConsistent) }

    /// Counts a piece of work in for the length of `body`, and gives what `body` gives.
    func counting<Result>(_ body: () -> Result) -> Result {
        let now = current.add(1, ordering: .sequentiallyConsistent).newValue
        most.max(now, ordering: .sequentiallyConsistent)
        defer { current.subtract(1, ordering: .sequentiallyConsistent) }
        return body()
    }
}

/// Runs `body` on a new thread whose stack holds `stackSize` bytes, and gives what it gives once it ends.
private func onNewThread<Result: Sendable>(
    stackSize: Int, _ body: @escaping @Sendable () -> Result,
) async -> Result {
    await withCheckedContinuation { continuation in
        let thread = Thread { continuation.resume(returning: body()) }
        thread.stackSize = stackSize
        thread.start()
    }
}

struct StageThreadTests {
    @Test func `work handed from several threads at once runs one piece at a time, and gives each its result`() async {
        let occupancy = Occupancy()
        let results = await withTaskGroup(of: Int?.self) { group in
            // Each client hands over work that stays on the stage thread long enough for the others to arrive.
            for client in 0..<8 {
                group.addTask {
                    await onNewThread(stackSize: 512 << 10) {
                        StageThread.run { _ in
                            occupancy.counting {
                                Thread.sleep(forTimeInterval: 0.01)
                                return client
                            }
                        }
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        #expect(results.compactMap(\.self).sorted() == Array(0..<8))
        #expect(occupancy.mostAtOnce == 1)
    }

    @Test func `an error the work throws on the stage thread is thrown to the client`() {
        struct Failure: Error, Equatable {}
        #expect(throws: Failure()) { try StageThread.run { _ throws(Failure) in throw Failure() } }
    }

    @Test func `work handed from the stage thread runs there at once`() {
        let result = StageThread.run { _ in StageThread.run { _ in 1 } }
        #expect(result == 1)
    }
}
