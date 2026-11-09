// swift-tools-version: 6.0
import CompilerPluginSupport
import Foundation
import PackageDescription

/// The major release of LLVM whose C API `rayoc` compiles programs with.
let llvmMajorVersion = 23

/// The directory LLVM `llvmMajorVersion` is installed under: `LLVM_PREFIX` when it's set, and otherwise the first
/// of the places a package manager installs it that holds that release.
let llvmPrefix: String = {
    let candidates = Context.environment["LLVM_PREFIX"].map { [$0] } ?? [
        "/usr/lib/llvm-\(llvmMajorVersion)",
        "/opt/homebrew/opt/llvm@\(llvmMajorVersion)",
        "/opt/homebrew/opt/llvm",
        "/usr/local/opt/llvm@\(llvmMajorVersion)",
        "/usr/local/opt/llvm",
    ]
    let installs = candidates.compactMap { candidate in llvmMajorVersion(at: candidate).map { (candidate, $0) } }
    if let match = installs.first(where: { $0.1 == llvmMajorVersion }) { return match.0 }
    let others = installs.map { "LLVM \($0.1) in \($0.0)" }
    fatalError("""
        rayoc builds against LLVM \(llvmMajorVersion), and found it in none of \(candidates)\
        \(others.isEmpty ? "" : ", only \(others.joined(separator: " and "))"): install it as TOOLCHAIN.md says, \
        or set LLVM_PREFIX to the directory it's installed under, then run 'swift package purge-cache'
        """)
}()

/// The directory that holds LLD `llvmMajorVersion`: `LLD_PREFIX`'s `bin` when it's set, and otherwise that of the
/// first of LLVM's prefix and the places a package manager installs LLD that holds that release. Where none does,
/// it is LLVM's own `bin`, so that `rayoc` reports LLD missing from there.
let lldDirectory: String = {
    if let prefix = Context.environment["LLD_PREFIX"] { return prefix + "/bin" }
    let candidates = [
        llvmPrefix,
        "/usr/lib/llvm-\(llvmMajorVersion)",
        "/opt/homebrew/opt/lld@\(llvmMajorVersion)",
        "/opt/homebrew/opt/lld",
        "/usr/local/opt/lld@\(llvmMajorVersion)",
        "/usr/local/opt/lld",
    ]
    let prefix = candidates.first { lldMajorVersion(at: $0) == llvmMajorVersion } ?? llvmPrefix
    return prefix + "/bin"
}()

/// The major release of the LLD installed under `prefix`, or nil when none is. LLD's own version file says it,
/// and otherwise an LLVM installed with it under the same prefix does.
func lldMajorVersion(at prefix: String) -> Int? {
    guard FileManager.default.fileExists(atPath: prefix + "/bin/lld") else { return nil }
    let definition = "set(PACKAGE_VERSION \""
    let config = try? String(contentsOfFile: prefix + "/lib/cmake/lld/LLDConfigVersion.cmake", encoding: .utf8)
    let line = config?.split(separator: "\n").first { $0.hasPrefix(definition) }
    let major = line.flatMap { Int($0.dropFirst(definition.count).prefix { $0.isNumber }) }
    return major ?? llvmMajorVersion(at: prefix)
}

/// `path`, which the manifest writes into C string literals, so it can't hold a quote or a backslash.
func checkedForDefine(_ path: String) -> String {
    if path.contains("\"") || path.contains("\\") {
        fatalError("rayoc can't be built against an LLVM whose path holds a quote or a backslash: \(path)")
    }
    return path
}

/// The major release of the LLVM installed under `prefix`, or nil when none is.
func llvmMajorVersion(at prefix: String) -> Int? {
    let definition = "#define LLVM_VERSION_MAJOR "
    let config = try? String(contentsOfFile: prefix + "/include/llvm/Config/llvm-config.h", encoding: .utf8)
    let line = config?.split(separator: "\n").first { $0.hasPrefix(definition) }
    return line.flatMap { Int($0.dropFirst(definition.count)) }
}

let package = Package(
    name: "Rayo",
    products: [
        .executable(name: "rayoc", targets: ["rayoc"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
    ],
    targets: [
        .macro(name: "RayoDiagnosticsMacros", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        ]),
        .target(name: "RayoSource"),
        .target(name: "RayoDiagnostics", dependencies: ["RayoDiagnosticsMacros", "RayoSource"]),
        .target(name: "RayoSyntax", dependencies: ["RayoDiagnostics", "RayoSource"]),
        .target(name: "RayoSema", dependencies: ["RayoDiagnostics", "RayoSource", "RayoSyntax"]),
        .target(name: "RayoIR", dependencies: ["RayoSema", "RayoSource", "RayoSyntax"]),
        .systemLibrary(name: "CLLVM"),
        .target(name: "RayoRuntime", resources: [
            .embedInCode("entry.ll"),
            .embedInCode("print.ll"),
            .embedInCode("panic.ll"),
        ]),
        .target(
            name: "RayoLLVM",
            dependencies: ["CLLVM", "RayoIR", "RayoRuntime", "RayoSema", "RayoSource", "RayoSyntax"],
            linkerSettings: [.unsafeFlags(["-L\(llvmPrefix)/lib"]), .linkedLibrary("LLVM-\(llvmMajorVersion)")]
        ),
        .target(name: "RayoDriver", dependencies: [
            "RayoDiagnostics", "RayoSyntax", "RayoSema", "RayoIR", "RayoLLVM", "RayoRuntime",
        ]),
        .executableTarget(name: "rayoc", dependencies: ["RayoDriver"]),
        .testTarget(name: "RayoDiagnosticsTests", dependencies: ["RayoDiagnostics"]),
        .testTarget(name: "RayoDiagnosticsMacrosTests", dependencies: [
            "RayoDiagnosticsMacros",
            .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
        ]),
        .testTarget(name: "RayoSyntaxTests", dependencies: ["RayoDiagnostics", "RayoSyntax"]),
        .testTarget(name: "RayoDriverTests", dependencies: ["RayoDiagnostics", "RayoDriver"]),
    ]
)

// A target that imports RayoLLVM, however indirectly, loads CLLVM too, and so reads LLVM's headers and the
// directories of the tools that link a program, which CLLVM's header holds.
for target in package.targets where dependsOnCLLVM(target, among: package.targets) {
    target.swiftSettings = (target.swiftSettings ?? []) + [.unsafeFlags([
        "-Xcc", "-I\(llvmPrefix)/include",
        "-Xcc", "-DRAYO_LLVM_TOOL_DIRECTORY=\"\(checkedForDefine(llvmPrefix + "/bin"))\"",
        "-Xcc", "-DRAYO_LLD_DIRECTORY=\"\(checkedForDefine(lldDirectory))\"",
    ])]
}

/// Whether `target` depends on CLLVM, directly or through others of `targets`.
func dependsOnCLLVM(_ target: Target, among targets: [Target]) -> Bool {
    target.dependencies.contains { dependency in
        switch dependency {
        case .targetItem(let name, _), .byNameItem(let name, _):
            return name == "CLLVM" || targets.contains { $0.name == name && dependsOnCLLVM($0, among: targets) }
        default:
            return false
        }
    }
}
