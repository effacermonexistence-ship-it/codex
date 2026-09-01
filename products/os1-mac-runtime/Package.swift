// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OS1Runtime",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "os1", targets: ["OS1"]),
        .executable(name: "OS1App", targets: ["OS1App"]),
    ],
    targets: [
        .executableTarget(name: "OS1"),
        .executableTarget(name: "OS1App"),
    ]
)
