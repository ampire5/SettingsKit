// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SettingsKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SettingsKit", targets: ["SettingsKit"]),
    ],
    targets: [
        .target(name: "SettingsKit"),
        .executableTarget(name: "settings-demo", dependencies: ["SettingsKit"]),
        .testTarget(name: "SettingsKitTests", dependencies: ["SettingsKit"]),
    ],
    swiftLanguageModes: [.v5]
)
