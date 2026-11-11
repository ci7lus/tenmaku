// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tenmaku",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "TenmakuShared"),
        .executableTarget(name: "Tenmaku", dependencies: ["TenmakuShared"]),
        .executableTarget(name: "TenmakuGamma", dependencies: ["TenmakuShared"]),
        .executableTarget(name: "TenmakuCover", dependencies: ["TenmakuShared"]),
        .executableTarget(name: "TenmakuHelper", dependencies: ["TenmakuShared"]),
        .executableTarget(name: "TenmakuInput", dependencies: ["TenmakuShared"]),
        .testTarget(name: "TenmakuSharedTests", dependencies: ["TenmakuShared"]),
        .testTarget(name: "TenmakuTests", dependencies: ["Tenmaku", "TenmakuShared"]),
    ]
)
