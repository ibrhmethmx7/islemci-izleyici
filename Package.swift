// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IslemciIzleyici",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "IslemciIzleyici", path: "Sources/IslemciIzleyici")
    ]
)
