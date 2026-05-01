// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenshotSearchAutomator",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ScreenshotSearchAutomator",
            targets: ["ScreenshotSearchAutomator"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ScreenshotSearchAutomator"
        )
    ]
)