#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE_NAME="ScreenshotSearchAutomator"
APP_NAME="Screenshot Search Automator"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
CONFIGURATION="debug"
RUN_AFTER_BUILD=0

usage() {
    cat <<'EOF'
Usage: ./Scripts/build-app.sh [--release] [--run]

Options:
  --release    Build with swift build -c release
  --run        Launch the bundle executable after signing
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)
            CONFIGURATION="release"
            ;;
        --run)
            RUN_AFTER_BUILD=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

cd "$ROOT_DIR"

swift build -c "$CONFIGURATION"

BINARY_PATH="$ROOT_DIR/.build/$CONFIGURATION/$EXECUTABLE_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>local.screenshot-search-automator</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Capture a selected screen area and send it with a question to your AI API.</string>
</dict>
</plist>
EOF

if [[ -n "${AI_API_KEY:-}" ]]; then
    cat > "$RESOURCES_DIR/RuntimeConfig.json" <<EOF
{
  "apiKey": "${AI_API_KEY}",
  "model": "${AI_MODEL:-}"
}
EOF
fi

codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built app bundle at: $APP_BUNDLE"

if [[ "$RUN_AFTER_BUILD" -eq 1 ]]; then
    "$MACOS_DIR/$EXECUTABLE_NAME"
fi