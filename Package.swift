// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SpotiRex",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SpotiRex", targets: ["SpotiRex"])],
    targets: [
        .executableTarget(name: "SpotiRex"),
        .testTarget(name: "SpotiRexTests", dependencies: ["SpotiRex"])
    ]
)
