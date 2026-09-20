APP_NAME = MacToys
DIST_DIR = dist
APP_BUNDLE = $(DIST_DIR)/$(APP_NAME).app
MACOS_DIR = $(APP_BUNDLE)/Contents/MacOS
RESOURCES_DIR = $(APP_BUNDLE)/Contents/Resources
ICONSET_DIR = $(DIST_DIR)/AppIcon.iconset
ICON_SRC = Sources/MacToys/Assets.xcassets/AppIcon.appiconset/mactoys_app_icon.png
INPUT_METHODS_DIR ?= $(HOME)/Library/Input Methods

.PHONY: all build package run install clean icon web deploy-web reset-permissions

all: build

# ─── Swift Desktop App ──────────────────────────────────────

build:
	@echo "Stopping old instances..."
	@killall $(APP_NAME) 2>/dev/null || true
	@echo "Building $(APP_NAME)..."
	@$(MAKE) package

reset-permissions:
	@echo "Resetting stale permissions..."
	@tccutil reset Accessibility com.mactoys.inputmethod.MacToys 2>/dev/null || true
	@tccutil reset ScreenCapture com.mactoys.inputmethod.MacToys 2>/dev/null || true

package:
	@echo "Resolving dependencies..."
	@swift package resolve
	@echo "Checking MLX Metal shaders..."
	@if [ ! -f ".build/checkouts/mlx-swift/Source/Cmlx/default.metallib" ] && [ -d ".build/checkouts/mlx-swift/Source/Cmlx" ]; then \
		echo "Compiling MLX Metal shaders (this may take a minute)..."; \
		cd .build/checkouts/mlx-swift/Source/Cmlx && \
		find mlx-generated/metal mlx/mlx/backend/metal/kernels -name "*.metal" | xargs xcrun -sdk macosx metal -I. -Imlx -Imlx/mlx/backend/metal/kernels -c && \
		xcrun -sdk macosx metallib *.air -o default.metallib; \
	fi
	@swift build -c release -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Sources/MacToys/Info.plist
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	@cp .build/release/$(APP_NAME) $(MACOS_DIR)/
	@$(MAKE) icon
	@echo "Copying Info.plist..."
	@cp Sources/MacToys/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@echo "Copying Swift Package resources..."
	@cp -R .build/arm64-apple-macosx/release/*.bundle $(RESOURCES_DIR)/ 2>/dev/null || true
	@echo "Copying GEC Python sidecar..."
	@cp Resources/gec_server.py $(RESOURCES_DIR)/gec_server.py 2>/dev/null || true
	@cp -R Resources/t5_module $(RESOURCES_DIR)/t5_module 2>/dev/null || true
	@if [ -f ".build/checkouts/mlx-swift/Source/Cmlx/default.metallib" ]; then \
		cp ".build/checkouts/mlx-swift/Source/Cmlx/default.metallib" $(RESOURCES_DIR)/default.metallib; \
		mkdir -p $(APP_BUNDLE)/Contents/MacOS/Resources; \
		cp ".build/checkouts/mlx-swift/Source/Cmlx/default.metallib" $(APP_BUNDLE)/Contents/MacOS/Resources/default.metallib; \
	fi
	@echo "Code signing with ad-hoc..."
	@codesign --force --deep --sign - $(APP_BUNDLE)
	@touch "dist/.metadata_never_index"
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

install: reset-permissions build
	@echo "Installing to the current user's Input Methods folder..."
	@mkdir -p "$(INPUT_METHODS_DIR)"
	@rm -rf "$(INPUT_METHODS_DIR)/$(APP_NAME).app"
	@cp -R $(APP_BUNDLE) "$(INPUT_METHODS_DIR)/$(APP_NAME).app"
	@echo "Registering Input Method..."
	@/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$(INPUT_METHODS_DIR)/$(APP_NAME).app" || true
	@echo "✅ Installed to $(INPUT_METHODS_DIR)!"

# ─── Web Companion Apps ─────────────────────────────────────

web:
	@echo "Building web apps..."
	@cd WebApps/mobile-scanner && npm run build
	@echo "✅ Web build complete!"

deploy-web:
	@echo "Building and deploying web apps..."
	@chmod +x scripts/deploy-web.sh
	@scripts/deploy-web.sh

# ─── Utility ────────────────────────────────────────────────

clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DIST_DIR)
	@rm -rf .build
	@rm -rf WebApps/*/dist
	@echo "Clean complete."
