APP_NAME = MacToys
DIST_DIR = dist
APP_BUNDLE = $(DIST_DIR)/$(APP_NAME).app
MACOS_DIR = $(APP_BUNDLE)/Contents/MacOS
RESOURCES_DIR = $(APP_BUNDLE)/Contents/Resources
ICONSET_DIR = $(DIST_DIR)/AppIcon.iconset
ICON_SRC = Sources/MacToys/Assets.xcassets/AppIcon.appiconset/mactoys_app_icon.png

.PHONY: all build run install clean icon

all: build

build:
	@echo "Stopping old instances..."
	@killall $(APP_NAME) 2>/dev/null || true
	@echo "Building $(APP_NAME)..."
	@swift build -c release
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	@cp .build/release/$(APP_NAME) $(MACOS_DIR)/
	@$(MAKE) icon
	@echo "Creating Info.plist..."
	@echo '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n    <key>CFBundleExecutable</key>\n    <string>MacToys</string>\n    <key>CFBundleIdentifier</key>\n    <string>com.mactoys.app</string>\n    <key>CFBundleName</key>\n    <string>MacToys</string>\n    <key>CFBundleIconFile</key>\n    <string>AppIcon</string>\n    <key>CFBundlePackageType</key>\n    <string>APPL</string>\n    <key>CFBundleShortVersionString</key>\n    <string>1.0</string>\n    <key>CFBundleVersion</key>\n    <string>1</string>\n    <key>LSMinimumSystemVersion</key>\n    <string>14.0</string>\n    <key>LSUIElement</key>\n    <true/>\n</dict>\n</plist>' > $(APP_BUNDLE)/Contents/Info.plist
	@echo "Code signing with ad-hoc..."
	@codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "✅ Build complete! App is ready in ./$(APP_BUNDLE)"

icon:
	@if [ -f "$(ICON_SRC)" ]; then \
		echo "Generating App Icon..."; \
		mkdir -p $(ICONSET_DIR); \
		sips -z 16 16     "$(ICON_SRC)" --out "$(ICONSET_DIR)/icon_16x16.png" >/dev/null; \
		sips -z 32 32     "$(ICON_SRC)" --out "$(ICONSET_DIR)/icon_16x16@2x.png" >/dev/null; \
		sips -z 32 32     "$(ICON_SRC)" --out "$(ICONSET_DIR)/icon_32x32.png" >/dev/null; \
		sips -z 64 64     "$(ICON_SRC)" --out "$(ICONSET_DIR)/icon_32x32@2x.png" >/dev/null; \
		sips -z 128 128   "$(ICON_SRC)" --out "$(ICONSET_DIR)/icon_128x128.png" >/dev/null; \
		sips -z 256 256   "$(ICON_SRC)" --out "$(ICONSET_DIR)/icon_128x128@2x.png" >/dev/null; \
		sips -z 256 256   "$(ICON_SRC)" --out "$(ICONSET_DIR)/icon_256x256.png" >/dev/null; \
		sips -z 512 512   "$(ICON_SRC)" --out "$(ICONSET_DIR)/icon_256x256@2x.png" >/dev/null; \
		sips -z 512 512   "$(ICON_SRC)" --out "$(ICONSET_DIR)/icon_512x512.png" >/dev/null; \
		sips -z 1024 1024 "$(ICON_SRC)" --out "$(ICONSET_DIR)/icon_512x512@2x.png" >/dev/null; \
		iconutil -c icns "$(ICONSET_DIR)" -o "$(RESOURCES_DIR)/AppIcon.icns" 2>/dev/null; \
		rm -rf "$(ICONSET_DIR)"; \
	fi

run: build
	@echo "Launching $(APP_NAME) from dist folder..."
	@open $(APP_BUNDLE)

install: build
	@echo "Installing to Applications folder..."
	@rm -rf "/Applications/$(APP_NAME).app"
	@cp -R $(APP_BUNDLE) "/Applications/$(APP_NAME).app"
	@echo "✅ Installed to /Applications/$(APP_NAME).app"

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DIST_DIR)
	@rm -rf .build
	@echo "Clean complete."
