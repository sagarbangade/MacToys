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
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.9.4"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0")
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
            dependencies: [
                "MacToysKit"
            ],
            path: "Sources/Extensions/TypingAssist"
        ),
        .target(
            name: "GrammarChecker",
            dependencies: [
                "MacToysKit",
                "ClipboardManager",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ],
            path: "Sources/Extensions/GrammarChecker"
        ),
        .target(
            name: "SpellChecker",
            dependencies: ["MacToysKit"],
            path: "Sources/Extensions/SpellChecker"
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
                "TypingAssist",
                "SpellChecker",
                "GrammarChecker"
            ]
        ),
        .testTarget(
            name: "MacToysTests",
            dependencies: ["MacToys"]
        )
    ]
)
