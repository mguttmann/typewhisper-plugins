#!/bin/bash
set -euo pipefail

PLUGIN_DIR="$1"
PLATFORM="${2:-mac}"

if [ -z "$PLUGIN_DIR" ]; then
  echo "Usage: build-plugin.sh <plugin-dir> [platform]"
  exit 1
fi

MANIFEST="$PLUGIN_DIR/manifest.json"
if [ ! -f "$MANIFEST" ]; then
  echo "Error: manifest.json not found in $PLUGIN_DIR"
  exit 1
fi

SLUG=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['slug'])")
VERSION=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['version'])")
NAME=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['principalClass'])")

echo "Building $SLUG v$VERSION for $PLATFORM..."

SRC_DIR="$PLUGIN_DIR/src"
if [ ! -f "$SRC_DIR/Package.swift" ]; then
  echo "Error: Package.swift not found in $SRC_DIR"
  exit 1
fi

REPO_ROOT="$(pwd)"
DIST_DIR="$REPO_ROOT/dist"
mkdir -p "$DIST_DIR"

case "$PLATFORM" in
  mac)
    cd "$SRC_DIR"
    swift build -c release
    BUILD_DIR=".build/release"

    # Create .bundle structure
    BUNDLE_DIR="$NAME.bundle"
    rm -rf "$BUNDLE_DIR"
    mkdir -p "$BUNDLE_DIR/Contents/MacOS"
    mkdir -p "$BUNDLE_DIR/Contents/Resources"

    # Find the built dylib (target name may differ from principalClass)
    DYLIB=""
    for f in "$BUILD_DIR"/lib*.dylib; do
      case "$(basename "$f")" in
        libTypeWhisperPluginSDK.dylib) continue ;;
        *) DYLIB="$f"; break ;;
      esac
    done
    if [ -n "$DYLIB" ]; then
      cp "$DYLIB" "$BUNDLE_DIR/Contents/MacOS/$NAME"
    elif [ -f "$BUILD_DIR/$NAME" ]; then
      cp "$BUILD_DIR/$NAME" "$BUNDLE_DIR/Contents/MacOS/$NAME"
    else
      echo "Error: Could not find built binary"
      ls "$BUILD_DIR/"
      exit 1
    fi

    # Copy manifest.json to Resources
    cp "../manifest.json" "$BUNDLE_DIR/Contents/Resources/"

    # Copy icon if present
    if [ -f "../icon.png" ]; then
      cp "../icon.png" "$BUNDLE_DIR/Contents/Resources/"
    fi

    # Create Info.plist
    cat > "$BUNDLE_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$(python3 -c "import json; print(json.load(open('../manifest.json'))['id'])")</string>
    <key>CFBundleName</key>
    <string>$NAME</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>NSPrincipalClass</key>
    <string>$NAME</string>
</dict>
</plist>
PLIST

    OUTPUT="$DIST_DIR/${SLUG}-${VERSION}-mac.bundle.zip"
    zip -r "$OUTPUT" "$BUNDLE_DIR"
    rm -rf "$BUNDLE_DIR"
    cd "$REPO_ROOT"
    echo "Built: $OUTPUT"
    ;;

  windows)
    echo "Windows build not yet implemented"
    exit 1
    ;;

  *)
    echo "Unknown platform: $PLATFORM"
    exit 1
    ;;
esac
