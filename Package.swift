// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PingViewScan",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PingViewScan", targets: ["PingViewScan"])
    ],
    targets: [
        .executableTarget(
            name: "PingViewScan",
            path: "Sources/PingViewScan"
        )
    ]
)
