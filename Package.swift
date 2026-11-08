// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

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
        .target(name: "RayoDiagnostics", dependencies: ["RayoDiagnosticsMacros"]),
        .target(name: "RayoSyntax", dependencies: ["RayoDiagnostics"]),
        .target(name: "RayoSema", dependencies: ["RayoDiagnostics", "RayoSyntax"]),
        .target(name: "RayoIR", dependencies: ["RayoDiagnostics", "RayoSema", "RayoSyntax"]),
        .target(name: "RayoLLVM", dependencies: ["RayoDiagnostics", "RayoIR", "RayoSema", "RayoSyntax"]),
        .target(name: "RayoDriver", dependencies: ["RayoDiagnostics", "RayoSyntax", "RayoSema", "RayoIR", "RayoLLVM"]),
        .executableTarget(name: "rayoc", dependencies: ["RayoDriver"]),
        .testTarget(name: "RayoDiagnosticsTests", dependencies: ["RayoDiagnostics"]),
        .testTarget(name: "RayoDiagnosticsMacrosTests", dependencies: [
            "RayoDiagnosticsMacros",
            .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
        ]),
        .testTarget(name: "RayoSyntaxTests", dependencies: ["RayoDiagnostics", "RayoSyntax"]),
        .testTarget(name: "RayoDriverTests", dependencies: ["RayoDriver"]),
    ]
)
