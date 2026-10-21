// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Barkeep",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Barkeep", path: "Sources/Barkeep")
    ]
)
