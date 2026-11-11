import Foundation
import LLVMImportCheck
import PackageGraph

/// The modules that may import LLVM's C modules.
let allowedModules: Set<String> = ["RayoLLVM", "RayoLLVMInstall", "RayoLLVMTests"]

/// Reads the Swift files under `directories`, and returns their text by their paths relative to the current
/// directory, with `/` between the paths' components.
func swiftFiles(under directories: [String]) throws -> [String: String] {
    var files: [String: String] = [:]
    for directory in directories {
        // A directory the package lacks holds no file.
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { continue }
        for case let relative as String in enumerator where relative.hasSuffix(".swift") {
            // Windows separates the components with `\`, where the manifest's paths have `/`.
            let path = (directory + "/" + relative).replacingOccurrences(of: "\\", with: "/")
            files[path] = try String(contentsOfFile: path, encoding: .utf8)
        }
    }
    return files
}

// The one argument names a file of `swift package dump-package`'s output, and the current directory is the
// package's root; any other arguments are a misuse, which exits with 2.
let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 1, let packageFile = arguments.first else {
    FileHandle.standardError.write(Data("usage: check-llvm-imports <package.json>\n".utf8))
    exit(2)
}

// Check the package's Swift files, and write each violation to standard error; any violation fails the check.
do {
    let packageJSON = try Data(contentsOf: URL(fileURLWithPath: packageFile))
    let package = try JSONDecoder().decode(PackageTargets.self, from: packageJSON)
    let check = LLVMImportCheck(allowedModules: allowedModules)
    let violations = check.violations(in: try swiftFiles(under: ["Sources", "Tests"]), of: package)
    for violation in violations {
        FileHandle.standardError.write(Data((check.description(of: violation) + "\n").utf8))
    }
    if !violations.isEmpty { exit(1) }
} catch {
    // A file that can't be read or decoded fails the check, and says why.
    FileHandle.standardError.write(Data("check-llvm-imports: \(error)\n".utf8))
    exit(1)
}
