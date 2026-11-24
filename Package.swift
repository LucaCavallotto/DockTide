// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DockTide",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DockTide", targets: ["DockTide"])],
    targets: [
        .target(name: "DockTideCore"),
        .executableTarget(name: "DockTide", dependencies: ["DockTideCore"]),
        .executableTarget(name: "DockTideChecks", dependencies: ["DockTideCore"], path: "Checks/DockTideChecks")
    ]
)
