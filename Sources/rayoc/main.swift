#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import RayoSyntax

let usage = """
    usage: rayoc <command> <file>

    commands:
      parse    parse the file and print its syntax tree
    """

func readFile(_ path: String) -> String? {
    guard let handle = fopen(path, "rb") else { return nil }
    defer { fclose(handle) }
    var bytes: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
        let count = fread(&buffer, 1, buffer.count, handle)
        if count > 0 { bytes.append(contentsOf: buffer[0..<count]) }
        if count < buffer.count { break }
    }
    if ferror(handle) != 0 { return nil }
    return String(decoding: bytes, as: UTF8.self)
}

func printError(_ text: String) {
    fputs(text + "\n", stderr)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    printError(usage)
    exit(2)
}
let (command, path) = (arguments[1], arguments[2])
guard let source = readFile(path) else {
    printError("rayoc: can't read '\(path)'")
    exit(1)
}

switch command {
case "parse":
    let (file, diagnostics) = Parser.parse(source)
    for diagnostic in diagnostics { printError("\(path):\(diagnostic)") }
    if !diagnostics.isEmpty { exit(1) }
    print(file.dump)
default:
    printError(usage)
    exit(2)
}
