// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Snug",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Snug", path: "Sources/Snug")
    ]
)
