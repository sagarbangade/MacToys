# MacToys 🛠️

A native, lightning-fast macOS utility suite designed for power users and developers. MacToys provides a collection of essential tools built natively with Swift, SwiftUI, and AppKit.

## ✨ Features

- **Text Extractor (OCR)**: Instantly capture and extract text from anywhere on your screen.
- **Clipboard Manager**: Keep track of your clipboard history and easily access past snippets.
- **Color Picker**: A system-wide color picker to grab hex/RGB codes on the fly.
- **Screen Ruler**: Measure UI elements and distances across your screen.
- **Keep Awake**: Prevent your Mac from sleeping with a simple menu bar toggle.
- **Global Hotkeys**: Powered by a robust keyboard shortcut engine for instant access.

## 🏗️ Architecture

MacToys is designed as a modular **Swift Package**. 

- `MacToysKit`: The core framework handling permissions, modular registry, and shared utilities.
- `MacToys`: The main executable target that wires the modules together.
- Individual feature modules (`TextExtractor`, `ColorPicker`, etc.) are decoupled for easy development.

## 🚀 Getting Started

1. Clone this repository.
2. Double-click the **`Package.swift`** file to open the project natively in Xcode.
    - *Note: Do not look for an `.xcodeproj` file. Xcode supports Swift Packages natively.*
3. Select the `MacToys` target and hit **`Cmd + R`** to build and run.

### Permissions
On first launch, the app will guide you through granting **Accessibility permissions**, which are required for global hotkeys and clipboard monitoring to function correctly.

## 🛠️ Requirements
- macOS 15.0+
- Xcode 16+
