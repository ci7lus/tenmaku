// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tenmaku",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Tenmaku"),
        .executableTarget(name: "TenmakuGamma"),
        .executableTarget(name: "TenmakuCover"),
        .executableTarget(name: "TenmakuHelper"),
    ]
)
