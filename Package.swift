// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vela",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VelaCore", targets: ["VelaCore"]),
        .executable(name: "VelaApp", targets: ["VelaApp"]),
        .executable(name: "vela", targets: ["vela"]),
    ],
    targets: [
        .target(
            name: "VelaCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("Vision"),
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"]),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .executableTarget(name: "VelaApp", dependencies: ["VelaCore"]),
        .executableTarget(name: "vela", dependencies: ["VelaCore"]),
        .testTarget(name: "VelaCoreTests", dependencies: ["VelaCore"]),
    ],
    swiftLanguageModes: [.v5]
)
