// swift-tools-version: 6.0
import CompilerPluginSupport
import Foundation
import PackageDescription

/// The major release of LLVM whose C API `rayoc` compiles programs with.
let llvmMajorVersion = 23

// The manifest runs from top to bottom, so these lists come before `llvmPrefix` and `lldDirectory`, which read them
// as they are made.
#if os(Windows)
/// The places a package manager installs LLVM `llvmMajorVersion`, and LLD with it, with its headers: none, on Windows.
let packageManagerLLVMPrefixes: [String] = []
let packageManagerLLDPrefixes: [String] = []
#else
/// The places a package manager installs LLVM `llvmMajorVersion` with its headers.
let packageManagerLLVMPrefixes = [
    "/usr/lib/llvm-\(llvmMajorVersion)",
    "/opt/homebrew/opt/llvm@\(llvmMajorVersion)",
    "/opt/homebrew/opt/llvm",
    "/usr/local/opt/llvm@\(llvmMajorVersion)",
    "/usr/local/opt/llvm",
]

/// The places a package manager installs LLD `llvmMajorVersion`, some of them apart from LLVM.
let packageManagerLLDPrefixes = [
    "/usr/lib/llvm-\(llvmMajorVersion)",
    "/opt/homebrew/opt/lld@\(llvmMajorVersion)",
    "/opt/homebrew/opt/lld",
    "/usr/local/opt/lld@\(llvmMajorVersion)",
    "/usr/local/opt/lld",
]
#endif

/// The directory LLVM `llvmMajorVersion` is installed under: `LLVM_PREFIX` when it's set, and otherwise the first
/// of the places a package manager installs it that holds that release.
let llvmPrefix: String = {
    // Read the release installed under each candidate.
    let candidates = Context.environment["LLVM_PREFIX"].map { [manifestPath($0)] } ?? packageManagerLLVMPrefixes
    let installs = candidates.compactMap { candidate in llvmMajorVersion(at: candidate).map { (candidate, $0) } }

    // The first install of the release is the one to build against.
    if let match = installs.first(where: { $0.1 == llvmMajorVersion }) { return match.0 }

    // Without one, the build stops, and says what it found instead.
    let others = installs.map { "LLVM \($0.1) in \($0.0)" }
    fatalError("""
        rayoc builds against LLVM \(llvmMajorVersion), and found it in none of \(candidates)\
        \(others.isEmpty ? "" : ", only \(others.joined(separator: " and "))"): install it as TOOLCHAIN.md says, \
        or set LLVM_PREFIX to the directory it's installed under, then run 'swift package purge-cache'
        """)
}()

/// The directory that holds LLD `llvmMajorVersion`: `LLD_PREFIX`'s `bin` when it's set, and otherwise that of the
/// first of LLVM's prefix and the places a package manager installs LLD that holds that release. Where none does,
/// it is LLVM's own `bin`, so that `rayo` reports LLD missing from there.
let lldDirectory: String = {
    // `LLD_PREFIX` names the install to use.
    if let prefix = Context.environment["LLD_PREFIX"] { return manifestPath(prefix) + "/bin" }

    // Otherwise the first prefix that holds the release is the one, and LLVM's is where none does.
    let candidates = [llvmPrefix] + packageManagerLLDPrefixes
    let prefix = candidates.first { lldMajorVersion(at: $0) == llvmMajorVersion } ?? llvmPrefix
    return prefix + "/bin"
}()

/// `path`, from the environment, as the manifest writes paths: on Windows with each backslash a forward slash,
/// which Windows takes alike and a C string literal holds as it is.
func manifestPath(_ path: String) -> String {
    #if os(Windows)
    path.replacingOccurrences(of: "\\", with: "/")
    #else
    path
    #endif
}

/// The file name of the executable `name`: on Windows with `.exe`, and elsewhere `name` itself.
func executableName(_ name: String) -> String {
    #if os(Windows)
    name + ".exe"
    #else
    name
    #endif
}

/// The major release of the LLD installed under `prefix`, or nil when none is.
func lldMajorVersion(at prefix: String) -> Int? {
    // A prefix without the `lld` tool holds no LLD.
    guard FileManager.default.fileExists(atPath: prefix + "/bin/" + executableName("lld")) else { return nil }

    // LLD's version file says its release; without one, an LLVM installed with it under the same prefix does.
    let definition = "set(PACKAGE_VERSION \""
    let config = try? String(contentsOfFile: prefix + "/lib/cmake/lld/LLDConfigVersion.cmake", encoding: .utf8)
    // A file written on Windows may end its lines in "\r\n", which Swift reads as one newline character.
    let line = config?.split(whereSeparator: \.isNewline).first { $0.hasPrefix(definition) }
    let major = line.flatMap { Int($0.dropFirst(definition.count).prefix { $0.isNumber }) }
    return major ?? llvmMajorVersion(at: prefix)
}

/// `path`, which the manifest writes into C string literals, stopping the build when it holds a quote or a backslash.
func checkedForDefine(_ path: String) -> String {
    // A quote or a backslash would end or escape the literal early.
    if path.contains("\"") || path.contains("\\") {
        fatalError("rayoc can't be built against an LLVM whose path holds a quote or a backslash: \(path)")
    }
    return path
}

/// The major release of the LLVM installed under `prefix`, or nil when none is.
func llvmMajorVersion(at prefix: String) -> Int? {
    let definition = "#define LLVM_VERSION_MAJOR "
    let config = try? String(contentsOfFile: prefix + "/include/llvm/Config/llvm-config.h", encoding: .utf8)
    // A file written on Windows may end its lines in "\r\n", which Swift reads as one newline character.
    let line = config?.split(whereSeparator: \.isNewline).first { $0.hasPrefix(definition) }
    return line.flatMap { Int($0.dropFirst(definition.count)) }
}

let package = Package(
    name: "Rayo",
    products: [
        .executable(name: "rayo", targets: ["rayo"]),
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
        .target(name: "RayoOwnership", dependencies: ["RayoDiagnostics", "RayoIR", "RayoSema", "RayoSource"]),
        .systemLibrary(name: "CLLVM"),
        .target(name: "RayoLLVMInstall", dependencies: ["CLLVM"]),
        .target(name: "RayoRuntime", resources: [
            .embedInCode("entry.ll"),
            .embedInCode("print.ll"),
            .embedInCode("panic.ll"),
            .embedInCode("host-posix.ll"),
            .embedInCode("host-windows.ll"),
        ]),
        .target(
            name: "RayoLLVM",
            dependencies: ["CLLVM", "RayoIR", "RayoRuntime", "RayoSema", "RayoSource", "RayoSyntax"],
            // MSVC can't build LLVM as one shared library, so Windows links the one that holds LLVM's C API.
            linkerSettings: [
                .unsafeFlags(["-L\(llvmPrefix)/lib"]),
                .linkedLibrary("LLVM-\(llvmMajorVersion)", .when(platforms: [.macOS, .linux])),
                .linkedLibrary("LLVM-C", .when(platforms: [.windows])),
            ]
        ),
        .target(name: "RayoCompiler", dependencies: [
            "RayoDiagnostics", "RayoSyntax", "RayoSema", "RayoIR", "RayoOwnership", "RayoLLVM",
        ]),
        .executableTarget(name: "rayoc", dependencies: ["RayoCompiler"]),
        .target(name: "RayoDriver", dependencies: ["RayoLLVMInstall"]),
        .executableTarget(name: "rayo", dependencies: ["RayoDriver"]),
        .testTarget(name: "RayoDiagnosticsTests", dependencies: ["RayoDiagnostics"]),
        .testTarget(name: "RayoDiagnosticsMacrosTests", dependencies: [
            "RayoDiagnosticsMacros",
            .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
        ]),
        .testTarget(name: "RayoSyntaxTests", dependencies: ["RayoDiagnostics", "RayoSyntax"]),
        .testTarget(name: "RayoSemaTests", dependencies: ["RayoSema", "RayoSyntax"]),
        .testTarget(name: "RayoCompilerTests", dependencies: ["RayoCompiler", "RayoDiagnostics", "RayoSource"]),
        .target(name: "ToolStandIn", path: "Tests/ToolStandIn"),
        .executableTarget(name: "tool-stand-in", dependencies: ["ToolStandIn"], path: "Tests/tool-stand-in"),
        .target(name: "TestSelection", path: "Tests/TestSelection"),
        .executableTarget(name: "select-tests", dependencies: ["TestSelection"], path: "Tests/select-tests"),
        .testTarget(name: "TestSelectionTests", dependencies: ["TestSelection"]),
        // The driver's tests run the built `rayo`, `rayoc` and `tool-stand-in`, so they depend on all three.
        .testTarget(name: "RayoDriverTests", dependencies: [
            "rayo", "rayoc", "tool-stand-in", "RayoDriver", "RayoLLVMInstall", "RayoRuntime", "ToolStandIn",
        ]),
        .testTarget(name: "RayoIRTests", dependencies: [
            "RayoDiagnostics", "RayoIR", "RayoSema", "RayoSource", "RayoSyntax",
        ]),
        .testTarget(name: "RayoOwnershipTests", dependencies: [
            "RayoDiagnostics", "RayoIR", "RayoOwnership", "RayoSema", "RayoSource",
        ]),
        .systemLibrary(name: "CLLVMJIT", path: "Tests/CLLVMJIT"),
        .target(name: "RayoLLVMTestSupport", path: "Tests/RayoLLVMTestSupport"),
        .testTarget(name: "RayoLLVMTests", dependencies: [
            "CLLVM", "CLLVMJIT", "RayoIR", "RayoLLVM", "RayoLLVMInstall", "RayoLLVMTestSupport", "RayoSema",
            "RayoSource", "RayoSyntax",
        ]),
    ]
)

// A target that imports RayoLLVM, however indirectly, loads CLLVM too, and so reads LLVM's headers and the
// directories of the tools that link a program, which CLLVM's header holds. A target that imports CLLVMJIT reads
// LLVM's headers as well.
for target in package.targets where readsLLVMHeaders(target, among: package.targets) {
    target.swiftSettings = (target.swiftSettings ?? []) + [.unsafeFlags([
        "-Xcc", "-I\(llvmPrefix)/include",
        "-Xcc", "-DRAYO_LLVM_TOOL_DIRECTORY=\"\(checkedForDefine(llvmPrefix + "/bin"))\"",
        "-Xcc", "-DRAYO_LLD_DIRECTORY=\"\(checkedForDefine(lldDirectory))\"",
    ])]
}

/// Whether `target` reads LLVM's headers, directly or through others of `targets`.
func readsLLVMHeaders(_ target: Target, among targets: [Target]) -> Bool {
    target.dependencies.contains { dependency in
        switch dependency {
        // A dependency reaches LLVM's headers when it is CLLVM or CLLVMJIT, or one of `targets` that depends on
        // either.
        case .targetItem(let name, _), .byNameItem(let name, _):
            return ["CLLVM", "CLLVMJIT"].contains(name)
                || targets.contains { $0.name == name && readsLLVMHeaders($0, among: targets) }

        // A product of another package is neither.
        default:
            return false
        }
    }
}
