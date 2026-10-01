// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rayo",
    products: [
        .executable(name: "rayoc", targets: ["rayoc"]),
    ],
    targets: [
        .target(name: "RayoSyntax"),
        .executableTarget(name: "rayoc", dependencies: ["RayoSyntax"]),
        .testTarget(name: "RayoSyntaxTests", dependencies: ["RayoSyntax"]),
    ]
)
