import RayoIR
import RayoSyntax

/// Writes Rayo IR as an LLVM IR module that a C toolchain's linker turns into an executable.
public enum LLVMEmitter {
    /// The exit status of a program that panics.
    public static let panicExitStatus: Int32 = 101

    /// The module for `program`, whose panics name `sourcePath` as the file they happen in.
    public static func emit(_ program: IRProgram, sourcePath: String) -> String {
        var module = ModuleWriter(sourcePath: sourcePath)
        module.define(program.main, named: "rayo.main")
        return module.text
    }
}

/// Collects a module's function definitions and the constants they use.
struct ModuleWriter {
    let sourcePath: String
    var constants: [String] = []
    var definitions: [String] = []

    init(sourcePath: String) {
        self.sourcePath = sourcePath
    }

    var text: String {
        let runtime = """
            declare i32 @printf(ptr, ...)
            declare i32 @fflush(ptr)
            declare i64 @write(i32, ptr, i64)
            declare void @exit(i32) noreturn
            declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)
            declare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)
            declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)

            @rayo.int_format = private unnamed_addr constant [6 x i8] c"%lld\\0A\\00"

            ; Writes what the program printed before it reports the panic, so the report comes last.
            define private void @rayo.panic(ptr %message, i64 %length) noreturn {
              call i32 @fflush(ptr null)
              call i64 @write(i32 2, ptr %message, i64 %length)
              call void @exit(i32 \(LLVMEmitter.panicExitStatus))
              unreachable
            }

            define i32 @main() {
              call void @rayo.main()
              ret i32 0
            }

            """
        return ([runtime] + constants + definitions).joined(separator: "\n") + "\n"
    }

    mutating func define(_ function: IRFunction, named name: String) {
        var writer = FunctionWriter(function: function, module: self)
        let body = writer.write()
        self = writer.module
        definitions.append("define private void @\(name)() {\n\(body)}\n")
    }

    /// Adds a constant holding the report of a panic for `reason` at `range`, and returns its name and
    /// length.
    mutating func panicMessage(_ reason: String, at range: SourceRange) -> (name: String, length: Int) {
        let bytes = Array("\(sourcePath):\(range.start): panic: \(reason)\n".utf8)
        let name = "@rayo.panic_message.\(constants.count)"
        constants.append("\(name) = private unnamed_addr constant [\(bytes.count) x i8] c\"\(escaped(bytes))\"")
        return (name, bytes.count)
    }

    /// `bytes` as the text of an LLVM string constant, with each byte that isn't printable ASCII, and each
    /// quote and backslash, written as `\XX`.
    private func escaped(_ bytes: [UInt8]) -> String {
        bytes.map { byte in
            let printable = byte >= 0x20 && byte < 0x7F && byte != UInt8(ascii: "\"") && byte != UInt8(ascii: "\\")
            if printable { return String(UnicodeScalar(byte)) }
            let hex = String(byte, radix: 16, uppercase: true)
            return "\\" + (hex.count == 1 ? "0" + hex : hex)
        }.joined()
    }
}
