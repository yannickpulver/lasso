// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Lasso",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Lasso", path: "Sources/Lasso"),
        .testTarget(name: "LassoTests", dependencies: ["Lasso"], path: "Tests/LassoTests"),
    ]
)
