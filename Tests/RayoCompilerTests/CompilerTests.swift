import Testing
import RayoCompiler
import RayoDiagnostics

/// What a run of the compiler gave, and the files it wrote.
private struct Compiled {
    var result: CompilerResult
    var written: [String: [UInt8]]
}

/// Runs the compiler with `arguments` over the source files `files` holds, where `writable` says whether a file
/// may be written.
private func compile(
    _ arguments: [String], files: [String: String] = [:], writable: Bool = true,
) -> Compiled {
    var written: [String: [UInt8]] = [:]
    let result = Compiler.run(arguments, readFile: { files[$0].map { Array($0.utf8) } }) { path, bytes in
        // A file that can't be written keeps nothing.
        guard writable else { return false }
        written[path] = bytes
        return true
    }
    return Compiled(result: result, written: written)
}

/// Whether `bytes` start as an object file for the host does: a 64-bit Mach-O file, an ELF one, or a COFF one for
/// x86-64 or arm64.
private func isObjectFile(_ bytes: [UInt8]) -> Bool {
    let machO: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE]
    let elf: [UInt8] = [0x7F, 0x45, 0x4C, 0x46]
    // A COFF object file has no magic number; it starts with the machine it is for, little-endian.
    let coff: [[UInt8]] = [[0x64, 0x86], [0x64, 0xAA]]
    return bytes.starts(with: machO) || bytes.starts(with: elf) || coff.contains { bytes.starts(with: $0) }
}

struct CompilerTests {
    @Test func `'--check' checks the file, and writes nothing`() {
        let compiled = compile(["--check", "a.rayo"], files: ["a.rayo": "func main() { print(1) }"])
        #expect(compiled.result == CompilerResult(exitCode: 0, errors: ""))
        #expect(compiled.written.isEmpty)
    }

    @Test(arguments: [[], ["--debug"], ["--release"]])
    func `'-o' writes the file's object code to the path it names, in either build mode`(mode: [String]) throws {
        let compiled = compile(mode + ["-o", "a.o", "a.rayo"], files: ["a.rayo": "func main() { print(1) }"])
        #expect(compiled.result == CompilerResult(exitCode: 0, errors: ""))
        #expect(Array(compiled.written.keys) == ["a.o"])
        #expect(isObjectFile(try #require(compiled.written["a.o"])))
    }

    @Test(arguments: [["--check", "a.rayo"], ["-o", "a.o", "a.rayo"]])
    func `a program's errors fail the run, each as the file's path, the position, the code and the message`(
        arguments: [String],
    ) {
        let compiled = compile(arguments, files: ["a.rayo": "func f() {\n    let = 1\n    x = )\n}"])
        #expect(compiled.result.exitCode == 1)
        #expect(compiled.result.diagnostics.map(\.code) == [
            .missingBindingName(found: .token("=")), .missingExpression(found: .token(")")),
        ])
        #expect(compiled.result.errors == """
            a.rayo:2:9: error[E0113]: expected a name to bind, found '='
            a.rayo:3:9: error[E0115]: expected an expression, found ')'

            """)
        #expect(compiled.written.isEmpty)
    }

    @Test(arguments: [
        (["--check", "--", "-o"], [String]()), (["--check", "--", "--"], []), (["-o", "a.o", "--", "--check"], ["a.o"]),
    ])
    func `'--' ends the options, so the file after it may be named like one`(
        arguments: [String], written: [String],
    ) {
        let source = "func main() {}"
        let compiled = compile(arguments, files: ["-o": source, "--": source, "--check": source])
        #expect(compiled.result == CompilerResult(exitCode: 0, errors: ""))
        #expect(Array(compiled.written.keys) == written)
    }

    @Test func `a file that isn't UTF-8 is an error`() {
        let source = String(decoding: Array("func main() {\n    print(1) // é".utf8) + [0xFF], as: UTF8.self)
        let result = Compiler.run(["--check", "a.rayo"], readFile: { _ in Array(source.utf8.dropLast(3)) + [0xFF] }) {
            _, _ in true
        }
        #expect(result.exitCode == 1)
        #expect(result.diagnostics.map(\.code) == [.notUTF8])
    }

    @Test func `a file that can't be read fails the run`() {
        #expect(compile(["--check", "missing.rayo"]).result ==
            CompilerResult(exitCode: 1, errors: "rayoc: can't read 'missing.rayo'\n"))
    }

    @Test func `an object file that can't be written fails the run`() {
        let compiled = compile(["-o", "a.o", "a.rayo"], files: ["a.rayo": "func main() {}"], writable: false)
        #expect(compiled.result == CompilerResult(exitCode: 1, errors: "rayoc: can't write 'a.o'\n"))
    }

    @Test(arguments: [
        [], ["a.rayo"], ["--check"], ["-o"], ["-o", "a.o"], ["check", "a.rayo"], ["run", "a.rayo"],
        ["--check", "a.rayo", "b.rayo"], ["-o", "a.o", "a.rayo", "b.rayo"],
        ["--check", "-o", "a.o", "a.rayo"], ["-o", "a.o", "--check", "a.rayo"], ["--check", "--check", "a.rayo"],
        ["-o", "a.o", "-o", "b.o", "a.rayo"], ["--check", "--debug", "a.rayo"], ["--release", "--check", "a.rayo"],
        ["--debug", "--release", "-o", "a.o", "a.rayo"], ["--fast", "-o", "a.o", "a.rayo"],
        ["-o", "--check", "a.rayo"], ["-o", "a.o", "--debug"], ["--check", "--debug"],
        ["--check", "--"], ["--", "a.rayo"], ["--", "--check", "a.rayo"], ["--check", "--", "a.rayo", "b.rayo"],
        ["-o", "--", "a.rayo"], ["--check", "--", "--", "a.rayo"],
    ])
    func `arguments that name no one compile print the usage, and write nothing`(arguments: [String]) {
        let compiled = compile(arguments, files: ["a.rayo": "func main() {}", "b.rayo": "func main() {}"])
        #expect(compiled.result.exitCode == 2)
        #expect(compiled.result.errors.hasPrefix("usage: rayoc --check [--] <file>\n"))
        #expect(compiled.written.isEmpty)
    }
}
