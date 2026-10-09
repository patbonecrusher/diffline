// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Diffline",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DiffCore", path: "Sources/DiffCore"),
        .executableTarget(name: "Diffline", dependencies: ["DiffCore"], path: "Sources/Diffline"),
        .executableTarget(name: "MakeIcon", path: "Tools/MakeIcon"),
        .testTarget(name: "DiffCoreTests", dependencies: ["DiffCore"], path: "Tests/DiffCoreTests"),
    ]
)
