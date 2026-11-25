import RayoCompiler

/// Runs `rayoc` with `arguments` before the path of the file that holds `source`. It writes nothing, though every
/// write it asks for succeeds.
func run(_ arguments: [String], on source: String) -> CompilerResult {
    Compiler.run(arguments + ["main.rayo"], readFile: { $0 == "main.rayo" ? Array(source.utf8) : nil }) { _, _ in
        true
    }
}
