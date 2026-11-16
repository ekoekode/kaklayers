// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KaKLayers",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KaKLayersCore", targets: ["KaKLayersCore"]),
        .executable(name: "KaKLayers", targets: ["KaKLayersApp"]),
    ],
    targets: [
        .target(name: "KaKLayersCore"),
        .executableTarget(name: "KaKLayersApp", dependencies: ["KaKLayersCore"]),
        .executableTarget(name: "KaKLayersSelfTest", dependencies: ["KaKLayersCore"]),
    ]
)
