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
/// the host's architecture.
private func isObjectFile(_ bytes: [UInt8]) -> Bool {
    let machO: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE]
    let elf: [UInt8] = [0x7F, 0x45, 0x4C, 0x46]
    // A COFF object file has no magic number; it starts with the machine it is for, little-endian: 0xAA64 for
    // arm64, and 0x8664 for x86-64.
    #if arch(arm64)
    let coff: [UInt8] = [0x64, 0xAA]
    #else
    let coff: [UInt8] = [0x64, 0x86]
    #endif
    return bytes.starts(with: machO) || bytes.starts(with: elf) || bytes.starts(with: coff)
}

struct CompilerTests {
    @Test func `'--check' checks the file, and writes nothing`() {
        let compiled = compile(["--check", "a.rayo"], files: ["a.rayo": "func main() { print(1) }"])
        #expect(compiled.result == CompilerResult(exitCode: 0, errors: ""))
        #expect(compiled.written.isEmpty)
    }

    @Test(arguments: ["func double(_ n: Int) -> Int { n * 2 }", ""])
    func `'--check' checks a file without 'main' as a library`(source: String) {
        let library = compile(["--check", "lib.rayo"], files: ["lib.rayo": source])
        #expect(library.result == CompilerResult(exitCode: 0, errors: ""))
    }

    @Test func `'--check' reports only a library's own errors, and no missing 'main'`() {
        let wrong = compile(["--check", "lib.rayo"], files: ["lib.rayo": "func f() { print(x) }"])
        #expect(wrong.result.diagnostics.map(\.code) == [.notDeclared(name: "x")])
    }

    @Test func `'--emit=ir' prints the Rayo IR of a file that checks, and writes nothing`() {
        let compiled = compile(["--emit=ir", "a.rayo"], files: ["a.rayo": "func main() {\n    print(1)\n}"])
        #expect(compiled.result == CompilerResult(exitCode: 0, errors: "", standardOutput: """
            main "main()"

            func "main()"() -> Void {
            bb0:
              _ = call builtin "print(_: Int)"(1) @2:5-2:13
              return
            }

            """))
        #expect(compiled.written.isEmpty)
    }

    @Test func `'--emit=ir' prints the IR the emitter receives, with the end of each access after its last use`() {
        let source = "func main() {\n    let x = 1\n    print(x)\n}"
        let compiled = compile(["--emit=ir", "a.rayo"], files: ["a.rayo": source])
        #expect(compiled.result.standardOutput == """
            main "main()"

            func "main()"() -> Void {
              let %0 x: Int
            bb0:
              declare %0
              %0 @2:9-2:10 = operand 1 @2:13-2:14
              begin a0 read static %0 @3:11-3:12
              _ = call builtin "print(_: Int)"(a0) @3:5-3:13
              end a0
              return
            }

            """)
    }

    @Test func `'--emit=checked' prints the checked program of a file that checks, and writes nothing`() {
        let compiled = compile(["--emit=checked", "a.rayo"], files: ["a.rayo": "func main() {\n    print(1)\n}"])
        #expect(compiled.result == CompilerResult(exitCode: 0, errors: "", standardOutput: """
            main "main()"

            func "main()"() -> Void {
              expression
                call builtin "print(_: Int)": Void @2:5-2:13
                  int 1: Int @2:11-2:12
            }

            """))
        #expect(compiled.written.isEmpty)
    }

    @Test(arguments: ["--emit=checked", "--emit=ir"])
    func `'--emit' prints nothing for a file that doesn't check, and reports its errors`(option: String) {
        let source = "func main() {\n    let x = 1\n    let y = x\n    print(x)\n}"
        let compiled = compile([option, "a.rayo"], files: ["a.rayo": source])
        #expect(compiled.result.exitCode == 1)
        #expect(compiled.result.diagnostics.map(\.code) == [.usedAfterMove(name: "x")])
        #expect(compiled.result.standardOutput.isEmpty)
    }

    @Test func `the usage names each dump '--emit' prints`() {
        let usage = compile([]).result.errors
        #expect(usage.contains("rayoc [--warnings-as-errors] --emit=checked|ir [--] <file>\n"))
        #expect(usage.contains("--emit=checked"))
        #expect(usage.contains("--emit=ir"))
    }

    @Test(arguments: [[], ["--debug"], ["--release"]])
    func `'-o' makes no object code of a file without 'main', which is a library`(mode: [String]) {
        let compiled = compile(mode + ["-o", "lib.o", "lib.rayo"],
                               files: ["lib.rayo": "func double(_ n: Int) -> Int { n * 2 }"])
        #expect(compiled.result.exitCode == 1)
        #expect(compiled.result.diagnostics.map(\.code) == [.noMain])
        #expect(compiled.result.errors == """
            lib.rayo:1:1: error[E0201]: the file has no 'main' function, so it can't be built into \
            an executable or run

            """)
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
        let compiled = compile(arguments, files: ["a.rayo": "func main() {\n    let = 1\n    x = )\n}"])
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

    @Test func `each place an error labels is shown after it, as the file's path, the position and the label`() {
        let source = "func f() {\n    let x = 1\n    let y = x\n    print(x)\n}"
        let compiled = compile(["--check", "a.rayo"], files: ["a.rayo": source])
        #expect(compiled.result.exitCode == 1)
        #expect(compiled.result.errors == """
            a.rayo:4:11: error[E0302]: 'x' was moved
            a.rayo:3:13: note: moved here

            """)
    }

    @Test(arguments: [
        ["--warnings-as-errors", "--check", "a.rayo"], ["--check", "--warnings-as-errors", "a.rayo"],
        ["--warnings-as-errors", "-o", "a.o", "a.rayo"], ["--debug", "-o", "a.o", "--warnings-as-errors", "a.rayo"],
    ])
    func `'--warnings-as-errors' goes with any compile, and a program without warnings still compiles`(
        arguments: [String],
    ) {
        let compiled = compile(arguments, files: ["a.rayo": "func main() { print(1) }"])
        #expect(compiled.result == CompilerResult(exitCode: 0, errors: ""))
    }

    @Test(arguments: ["--emit=checked", "--emit=ir"])
    func `'--warnings-as-errors' goes with a dump, which a program without warnings still prints`(dump: String) {
        let source = ["a.rayo": "func main() { print(1) }"]
        let strict = compile(["--warnings-as-errors", dump, "a.rayo"], files: source).result
        #expect(strict.exitCode == 0)
        #expect(strict.errors == "")
        #expect(!strict.standardOutput.isEmpty)
        #expect(strict.standardOutput == compile([dump, "a.rayo"], files: source).result.standardOutput)
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
        ["--emit=asm", "a.rayo"], ["--emit", "a.rayo"], ["--emit=", "a.rayo"], ["--emit=ir", "--check", "a.rayo"],
        ["--check", "--emit=checked", "a.rayo"], ["--emit=ir", "-o", "a.o", "a.rayo"],
        ["--emit=ir", "--emit=checked", "a.rayo"], ["--emit=ir", "--debug", "a.rayo"], ["--emit=ir"],
        ["--warnings-as-errors", "a.rayo"], ["--check", "--warnings-as-errors"],
        ["--warnings-as-errors", "--warnings-as-errors", "--check", "a.rayo"],
    ])
    func `arguments that name no one compile print the usage, and write nothing`(arguments: [String]) {
        let compiled = compile(arguments, files: ["a.rayo": "func main() {}", "b.rayo": "func main() {}"])
        #expect(compiled.result.exitCode == 2)
        #expect(compiled.result.errors.hasPrefix("usage: rayoc [--warnings-as-errors] --check [--] <file>\n"))
        #expect(compiled.written.isEmpty)
    }
}
