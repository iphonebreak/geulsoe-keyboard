// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TadakDomain",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TadakDomain", targets: ["TadakDomain"])
    ],
    targets: [
        .target(name: "TadakDomain"),
        .testTarget(name: "TadakDomainTests", dependencies: ["TadakDomain"])
    ]
)
