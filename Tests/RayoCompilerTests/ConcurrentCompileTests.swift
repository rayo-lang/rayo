import Testing
import RayoCompiler

/// Runs `rayoc` with `arguments` before the path of the file that holds `source`, writing nothing.
private func run(_ arguments: [String], on source: String) -> CompilerResult {
    Compiler.run(arguments + ["main.rayo"], readFile: { $0 == "main.rayo" ? Array(source.utf8) : nil }) { _, _ in
        false
    }
}

/// Compiles that give different results, as the arguments and the source of each: one prints its IR, and one finds
/// an error.
private let compiles = [
    (["--emit=ir"], "func main() {\n    print(1 + 2)\n}\n"),
    (["--check"], "func main() {\n    print(x)\n}\n"),
]

struct ConcurrentCompileTests {
    @Test func `compiles handed over from several threads at once each give the result they give alone`() async {
        let alone = compiles.map { arguments, source in run(arguments, on: source) }
        #expect(alone.map(\.exitCode) == [0, 1])

        // Each compile starts on a thread of its own, whose stack is small, at the same time as the others.
        let together = await withTaskGroup(of: (Int, CompilerResult).self) { group in
            for (index, (arguments, source)) in compiles.enumerated() {
                group.addTask {
                    (index, await onNewThread(stackSize: smallStackSize) { run(arguments, on: source) })
                }
            }
            return await group.reduce(into: [:]) { results, compiled in results[compiled.0] = compiled.1 }
        }
        #expect(compiles.indices.map { together[$0] } == alone)
    }
}
