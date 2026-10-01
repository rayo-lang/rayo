// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rayo",
    products: [
        .executable(name: "rayoc", targets: ["rayoc"]),
    ],
    targets: [
        .target(name: "RayoSyntax"),
        .target(name: "RayoDriver", dependencies: ["RayoSyntax"]),
        .executableTarget(name: "rayoc", dependencies: ["RayoDriver"]),
        .testTarget(name: "RayoSyntaxTests", dependencies: ["RayoSyntax"]),
        .testTarget(name: "RayoDriverTests", dependencies: ["RayoDriver"]),
    ]
)
