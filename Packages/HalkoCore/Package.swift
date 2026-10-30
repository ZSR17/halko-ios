// swift-tools-version: 6.2
import PackageDescription

// Code shared by the iPhone and watch apps: nothing specific to iOS. macOS is only there for `swift test` on a Mac.
let package = Package(
    name: "HalkoCore",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "HalkoCore", targets: ["HalkoCore"]),
    ],
    targets: [
        .target(name: "HalkoCore", resources: [.copy("Resources/exercises.json"), .copy("Resources/body-paths.json")]),
        .testTarget(name: "HalkoCoreTests", dependencies: ["HalkoCore"]),
    ]
)
