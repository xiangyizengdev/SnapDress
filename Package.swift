// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SnapDress",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SnapDress",
            dependencies: ["KeyboardShortcuts"],
            path: "SnapDress",
            exclude: [
                "Info.plist",
            ],
            resources: [
                .process("Assets.xcassets"),
            ],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
    ]
)
