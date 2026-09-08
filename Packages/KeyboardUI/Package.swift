// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyboardUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KeyboardUI", targets: ["KeyboardUI"])
    ],
    dependencies: [
        .package(path: "../KeyboardCore"),
        .package(path: "../TadakDomain")
    ],
    targets: [
        .target(
            name: "KeyboardUI",
            dependencies: ["KeyboardCore", "TadakDomain"]
        ),
        .testTarget(name: "KeyboardUITests", dependencies: ["KeyboardUI"])
    ]
)
