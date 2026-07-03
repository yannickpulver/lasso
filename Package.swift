// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CircleToSearch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "CircleToSearch", path: "Sources/CircleToSearch"),
        .testTarget(name: "CircleToSearchTests", dependencies: ["CircleToSearch"], path: "Tests/CircleToSearchTests"),
    ]
)
