APP_NAME = Chilltrax
EXECUTABLE_NAME = Mactrax
BUNDLE_DIR = $(APP_NAME).app
CONTENTS_DIR = $(BUNDLE_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

.PHONY: all build app run test clean

all: app

build:
	swift build -c release

app: build
	@rm -rf "$(RESOURCES_DIR)"
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	@rm -rf /tmp/MactraxAppIcon.iconset /tmp/AppIcon.icon
	@if xcrun -f actool >/dev/null 2>&1; then \
		.build/release/$(EXECUTABLE_NAME) --export-icon-bundle /tmp/AppIcon.icon && \
		xcrun actool /tmp/AppIcon.icon --compile "$(RESOURCES_DIR)" --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist /tmp/MactraxIconPartial.plist >/dev/null && \
		rm -rf /tmp/AppIcon.icon /tmp/MactraxIconPartial.plist; \
	fi
	@.build/release/$(EXECUTABLE_NAME) --export-iconset /tmp/MactraxAppIcon.iconset && iconutil -c icns /tmp/MactraxAppIcon.iconset -o "$(RESOURCES_DIR)/AppIcon.icns" && rm -rf /tmp/MactraxAppIcon.iconset
	@cp ".build/release/$(EXECUTABLE_NAME)" "$(MACOS_DIR)/$(APP_NAME)"
	@printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'    <key>CFBundleExecutable</key>' \
		'    <string>$(APP_NAME)</string>' \
		'    <key>CFBundleIconFile</key>' \
		'    <string>AppIcon</string>' \
		'    <key>CFBundleIconName</key>' \
		'    <string>AppIcon</string>' \
		'    <key>CFBundleIdentifier</key>' \
		'    <string>com.lucianmarin.mactrax</string>' \
		'    <key>CFBundleName</key>' \
		'    <string>$(APP_NAME)</string>' \
		'    <key>CFBundleDisplayName</key>' \
		'    <string>$(APP_NAME)</string>' \
		'    <key>CFBundlePackageType</key>' \
		'    <string>APPL</string>' \
		'    <key>CFBundleShortVersionString</key>' \
		'    <string>2.3</string>' \
		'    <key>CFBundleVersion</key>' \
		'    <string>15</string>' \
		'    <key>LSMinimumSystemVersion</key>' \
		'    <string>14.0</string>' \
		'    <key>NSHighResolutionCapable</key>' \
		'    <true/>' \
		'    <key>NSPrincipalClass</key>' \
		'    <string>NSApplication</string>' \
		'    <key>NSAppTransportSecurity</key>' \
		'    <dict>' \
		'        <key>NSAllowsArbitraryLoads</key>' \
		'        <true/>' \
		'        <key>NSAllowsArbitraryLoadsInMedia</key>' \
		'        <true/>' \
		'    </dict>' \
		'</dict>' \
		'</plist>' > "$(CONTENTS_DIR)/Info.plist"
	@codesign --force --deep --sign - "$(BUNDLE_DIR)" >/dev/null 2>&1 || true
	@echo "Built $(BUNDLE_DIR)"

run: app
	open "$(BUNDLE_DIR)"

test:
	swift test

clean:
	swift package clean
	rm -rf "$(BUNDLE_DIR)"
