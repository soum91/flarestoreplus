// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "FlareStorePlusCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "FlareStorePlusCore", targets: ["FlareStorePlusCore"])],
    targets: [
        .target(name: "FlareStorePlusCore"),
        .testTarget(name: "FlareStorePlusCoreTests", dependencies: ["FlareStorePlusCore"]),
    ]
)