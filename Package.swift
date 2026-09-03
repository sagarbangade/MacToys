// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacToys",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MacToys", targets: ["MacToys"]),
        .library(name: "MacToysKit", targets: ["MacToysKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.9.4")
    ],
    targets: [
        .target(
            name: "MacToysKit",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ]
        ),
        .target(
            name: "TextExtractor",
            dependencies: ["MacToysKit"]
        ),
        .target(
            name: "ColorPicker",
            dependencies: ["MacToysKit"]
        ),
        .target(
            name: "KeepAwake",
            dependencies: ["MacToysKit"]
        ),
        .target(
            name: "ScreenRuler",
            dependencies: ["MacToysKit"]
        ),
        .target(
            name: "ClipboardManager",
            dependencies: ["MacToysKit"]
        ),
        .executableTarget(
            name: "MacToys",
            dependencies: [
                "MacToysKit", 
                "TextExtractor", 
                "ColorPicker", 
                "KeepAwake", 
                "ScreenRuler",
                "ClipboardManager"
            ]
        ),
        .testTarget(
            name: "MacToysTests",
            dependencies: ["MacToys"]
        )
    ]
)
