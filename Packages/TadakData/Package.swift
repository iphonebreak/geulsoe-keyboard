// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TadakData",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TadakData", targets: ["TadakData"])
    ],
    dependencies: [
        .package(path: "../TadakDomain")
    ],
    targets: [
        .target(
            name: "TadakData",
            dependencies: ["TadakDomain"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "TadakDataTests", dependencies: ["TadakData"])
    ]
)
