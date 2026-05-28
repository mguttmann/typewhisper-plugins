#!/usr/bin/env bash
# Build and install the Claude (OAuth Pro/Max) plugin into TypeWhisper on macOS.
#
# Run this from the plugins/claude-oauth/ directory after cloning the repo:
#   ./install.sh
#
# What it does:
#   1. swift build -c release  (in ./src)
#   2. Assemble ClaudeOAuthPlugin.bundle (Contents/MacOS, Contents/Resources, Info.plist)
#   3. Patch the SDK reference from @rpath/libTypeWhisperPluginSDK.dylib (SPM output)
#      to @rpath/TypeWhisperPluginSDK.framework/Versions/A/TypeWhisperPluginSDK
#      (what TypeWhisper.app actually ships)
#   4. Add /Applications/TypeWhisper.app/Contents/Frameworks as an LC_RPATH so the
#      framework resolves at runtime
#   5. Ad-hoc code-sign the bundle
#   6. Copy it into ~/Library/Application Support/TypeWhisper/Plugins/
#
# After it finishes, quit and restart TypeWhisper, then activate the plugin under
# Settings -> Plugins -> Claude (OAuth Pro/Max).
#
# Requirements: macOS 14+, Xcode command line tools (swift), TypeWhisper.app installed.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PLUGIN_ROOT"

EXECUTABLE_NAME="ClaudeOAuthPlugin"
BUNDLE_NAME="ClaudeOAuthPlugin.bundle"
BUNDLE_PATH="${PLUGIN_ROOT}/build/${BUNDLE_NAME}"
TYPEWHISPER_APP="/Applications/TypeWhisper.app"
TYPEWHISPER_FRAMEWORKS="${TYPEWHISPER_APP}/Contents/Frameworks"
PLUGINS_DIR="${HOME}/Library/Application Support/TypeWhisper/Plugins"

# --- Preflight checks -------------------------------------------------------

if ! command -v swift >/dev/null 2>&1; then
  echo "Error: 'swift' not found. Install Xcode command line tools: xcode-select --install" >&2
  exit 1
fi

if [ ! -d "$TYPEWHISPER_APP" ]; then
  echo "Error: TypeWhisper.app not found at $TYPEWHISPER_APP." >&2
  echo "Install TypeWhisper first (https://typewhisper.com), then re-run." >&2
  exit 1
fi

VERSION=$(python3 -c "import json; print(json.load(open('manifest.json'))['version'])")

# --- 1. Build ---------------------------------------------------------------

echo "==> swift build -c release (this fetches the SDK on first run, ~30-60s)"
( cd src && swift build -c release )

DYLIB="src/.build/release/lib${EXECUTABLE_NAME}.dylib"
if [ ! -f "$DYLIB" ]; then
  echo "Error: expected build output $DYLIB not found." >&2
  exit 1
fi

# --- 2. Assemble the .bundle ------------------------------------------------

echo "==> Assemble ${BUNDLE_NAME}"
rm -rf "${BUNDLE_PATH}"
mkdir -p "${BUNDLE_PATH}/Contents/MacOS" "${BUNDLE_PATH}/Contents/Resources"
cp "$DYLIB" "${BUNDLE_PATH}/Contents/MacOS/${EXECUTABLE_NAME}"
cp manifest.json "${BUNDLE_PATH}/Contents/Resources/manifest.json"

cat > "${BUNDLE_PATH}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleDisplayName</key><string>Claude (OAuth Pro/Max)</string>
	<key>CFBundleExecutable</key><string>${EXECUTABLE_NAME}</string>
	<key>CFBundleIdentifier</key><string>com.guttmann.typewhisper-claude-oauth</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>${EXECUTABLE_NAME}</string>
	<key>CFBundlePackageType</key><string>BNDL</string>
	<key>CFBundleShortVersionString</key><string>${VERSION}</string>
	<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSPrincipalClass</key><string>ClaudeOAuthLLMPlugin</string>
</dict>
</plist>
EOF

# --- 3 + 4. Patch the Mach-O so it finds the SDK framework at runtime -------

echo "==> Patch SDK reference + rpath"
install_name_tool -change \
  "@rpath/lib${EXECUTABLE_NAME}.dylib" \
  "@rpath/${EXECUTABLE_NAME}" \
  "${BUNDLE_PATH}/Contents/MacOS/${EXECUTABLE_NAME}" 2>/dev/null || true
install_name_tool -change \
  "@rpath/libTypeWhisperPluginSDK.dylib" \
  "@rpath/TypeWhisperPluginSDK.framework/Versions/A/TypeWhisperPluginSDK" \
  "${BUNDLE_PATH}/Contents/MacOS/${EXECUTABLE_NAME}"
install_name_tool -add_rpath \
  "${TYPEWHISPER_FRAMEWORKS}" \
  "${BUNDLE_PATH}/Contents/MacOS/${EXECUTABLE_NAME}" 2>/dev/null || true

# --- 5. Ad-hoc code sign ----------------------------------------------------

echo "==> Ad-hoc code sign"
codesign --force --sign - --timestamp=none "${BUNDLE_PATH}"
codesign --verify --verbose "${BUNDLE_PATH}"

# --- 6. Install -------------------------------------------------------------

echo "==> Install to ${PLUGINS_DIR}/"
mkdir -p "${PLUGINS_DIR}"
rm -rf "${PLUGINS_DIR}/${BUNDLE_NAME}"
cp -R "${BUNDLE_PATH}" "${PLUGINS_DIR}/"

echo
echo "Done. Installed Claude (OAuth Pro/Max) v${VERSION}."
echo "Quit and restart TypeWhisper, then activate it under:"
echo "  Settings -> Plugins -> Claude (OAuth Pro/Max)"
