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
    let version = "#define LLVM_VERSION_MAJOR \(llvmMajorVersion)\n"
    let prefix = candidates.first { candidate in
        let config = try? String(contentsOfFile: candidate + "/include/llvm/Config/llvm-config.h", encoding: .utf8)
        return config?.contains(version) ?? false
    }
    guard let prefix else {
        fatalError("""
            rayoc builds against LLVM \(llvmMajorVersion), and found it in none of \(candidates): \
            install it as TOOLCHAIN.md says, or set LLVM_PREFIX to the directory it's installed under
            """)
    }
    return prefix
}()

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
    ]
)

// Every target that imports RayoLLVM, however indirectly, loads CLLVM and so reads LLVM's headers.
for target in package.targets where target.type != .system {
    target.swiftSettings = (target.swiftSettings ?? []) + [.unsafeFlags(["-Xcc", "-I\(llvmPrefix)/include"])]
}
