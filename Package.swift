// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Crest", platforms: [.macOS(.v14)],
    products: [.executable(name: "Crest", targets: ["Crest"]), .executable(name: "crest-bridge", targets: ["CrestBridge"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "CrestCore"),
        .executableTarget(name: "Crest", dependencies: ["CrestCore", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "CrestBridge", dependencies: ["CrestCore"]),
        .executableTarget(name: "CrestChecks", dependencies: ["CrestCore"], path: "Tests/CrestCoreTests")
    ])
