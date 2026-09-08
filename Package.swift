// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacToys",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacToys", targets: ["MacToys"]),
        .library(name: "MacToysKit", targets: ["MacToysKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.9.4")
    ],
    targets: [
        // ─── Core SDK ───────────────────────────────────────────
        .target(
            name: "MacToysKit",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ]
        ),

        // ─── Extensions ─────────────────────────────────────────
        .target(
            name: "TextExtractor",
            dependencies: ["MacToysKit"],
            path: "Sources/Extensions/TextExtractor"
        ),
        .target(
            name: "ColorPicker",
            dependencies: ["MacToysKit"],
            path: "Sources/Extensions/ColorPicker"
        ),
        .target(
            name: "KeepAwake",
            dependencies: ["MacToysKit"],
            path: "Sources/Extensions/KeepAwake"
        ),
        .target(
            name: "ScreenRuler",
            dependencies: ["MacToysKit"],
            path: "Sources/Extensions/ScreenRuler"
        ),
        .target(
            name: "ClipboardManager",
            dependencies: ["MacToysKit"],
            path: "Sources/Extensions/ClipboardManager"
        ),
        .target(
            name: "QRScanner",
            dependencies: ["MacToysKit"],
            path: "Sources/Extensions/QRScanner"
        ),
        .target(
            name: "MobileScanner",
            dependencies: ["MacToysKit", "TextExtractor"],
            path: "Sources/Extensions/MobileScanner"
        ),
        .target(
            name: "TypingAssist",
            dependencies: ["MacToysKit"],
            path: "Sources/Extensions/TypingAssist"
        ),

        // ─── App Shell ──────────────────────────────────────────
        .executableTarget(
            name: "MacToys",
            dependencies: [
                "MacToysKit",
                "TextExtractor",
                "ColorPicker",
                "KeepAwake",
                "ScreenRuler",
                "ClipboardManager",
                "QRScanner",
                "MobileScanner",
                "TypingAssist"
            ]
        ),
        .testTarget(
            name: "MacToysTests",
            dependencies: ["MacToys"]
        )
    ]
)
