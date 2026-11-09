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
        .target(
            name: "RayoLLVM",
            dependencies: ["CLLVM", "RayoIR", "RayoSema", "RayoSource", "RayoSyntax"],
            linkerSettings: [.unsafeFlags(["-L\(llvmPrefix)/lib"]), .linkedLibrary("LLVM-\(llvmMajorVersion)")]
        ),
        .target(name: "RayoDriver", dependencies: ["RayoDiagnostics", "RayoSyntax", "RayoSema", "RayoIR", "RayoLLVM"]),
        .executableTarget(name: "rayoc", dependencies: ["RayoDriver"]),
        .testTarget(name: "RayoDiagnosticsTests", dependencies: ["RayoDiagnostics"]),
        .testTarget(name: "RayoDiagnosticsMacrosTests", dependencies: [
            "RayoDiagnosticsMacros",
            .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
        ]),
        .testTarget(name: "RayoSyntaxTests", dependencies: ["RayoDiagnostics", "RayoSyntax"]),
        .testTarget(name: "RayoDriverTests", dependencies: ["RayoDiagnostics", "RayoDriver"]),
        .testTarget(name: "RayoLLVMTests", dependencies: [
            "CLLVM", "RayoIR", "RayoLLVM", "RayoSema", "RayoSource", "RayoSyntax",
        ]),
    ]
)

// A target that imports RayoLLVM, however indirectly, loads CLLVM too, and so reads LLVM's headers and the
// directory of LLVM's tools, which CLLVM's header holds.
for target in package.targets where dependsOnCLLVM(target, among: package.targets) {
    target.swiftSettings = (target.swiftSettings ?? []) + [.unsafeFlags([
        "-Xcc", "-I\(llvmPrefix)/include",
        "-Xcc", "-DRAYO_LLVM_TOOL_DIRECTORY=\"\(checkedForDefine(llvmPrefix + "/bin"))\"",
    ])]
}

/// `path`, which the manifest writes into a C string literal, so it can't hold a quote or a backslash.
func checkedForDefine(_ path: String) -> String {
    if path.contains("\"") || path.contains("\\") {
        fatalError("rayoc can't be built against an LLVM whose path holds a quote or a backslash: \(path)")
    }
    return path
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
