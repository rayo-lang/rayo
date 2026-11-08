// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rayo",
    products: [
        .executable(name: "rayoc", targets: ["rayoc"]),
    ],
    targets: [
        .target(name: "RayoSyntax"),
        .target(name: "RayoSema", dependencies: ["RayoSyntax"]),
        .target(name: "RayoIR", dependencies: ["RayoSema", "RayoSyntax"]),
        .target(name: "RayoLLVM", dependencies: ["RayoIR", "RayoSema", "RayoSyntax"]),
        .target(name: "RayoDriver", dependencies: ["RayoSyntax", "RayoSema", "RayoIR", "RayoLLVM"]),
        .executableTarget(name: "rayoc", dependencies: ["RayoDriver"]),
        .testTarget(name: "RayoSyntaxTests", dependencies: ["RayoSyntax"]),
        .testTarget(name: "RayoDriverTests", dependencies: ["RayoDriver"]),
    ]
)
