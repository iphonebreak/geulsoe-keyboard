// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyboardCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KeyboardCore", targets: ["KeyboardCore"])
    ],
    dependencies: [
        .package(path: "../HangulEngine"),
        .package(path: "../TadakDomain")
    ],
    targets: [
        .target(
            name: "KeyboardCore",
            dependencies: ["HangulEngine", "TadakDomain"]
        ),
        .testTarget(name: "KeyboardCoreTests", dependencies: ["KeyboardCore"])
    ]
)
