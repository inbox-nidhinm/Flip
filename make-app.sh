#!/bin/bash
# Wraps the built executable in a real .app bundle, so it gets a Dock icon,
# proper focus behaviour, and can be double-clicked like anything else.
set -euo pipefail

cd "$(dirname "$0")"
CONFIG="${1:-release}"

# SwiftPM stamps the binary as built for its oldest supported macOS (15)
# rather than the SDK it was built with, and AppKit draws an app as the macOS
# it says it was built for: the flat traffic lights of 15 instead of the glossy
# ones Twine has. This stamps the real SDK version and keeps 15 as the oldest.
SDK_VERSION="$(xcrun --show-sdk-version)"
LINK=(-Xlinker -platform_version -Xlinker macos -Xlinker 15.0 -Xlinker "$SDK_VERSION")

swift build -c "$CONFIG" "${LINK[@]}"
BIN="$(swift build -c "$CONFIG" "${LINK[@]}" --show-bin-path)/Flip"

# Recompose the icon if the artwork is newer than the built .icns. Building
# without artwork is fine — the app just takes the generic icon.
ICON_KEYS=""
ART=""
for candidate in Icon/source.png Icon/icon.png; do
    [ -f "$candidate" ] && ART="$candidate" && break
done
if [ -n "$ART" ]; then
    if [ ! -f Resources/AppIcon.icns ] || [ "$ART" -nt Resources/AppIcon.icns ]; then
        swift Tools/make-icon.swift "$ART" Resources/AppIcon.icns
    fi
    ICON_KEYS='    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundleIconName</key>          <string>AppIcon</string>'
fi

APP="build/Flip.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Flip"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# The panel grain, as SwiftPM's generated resource bundle. It has to land in
# Contents/Resources specifically: `Bundle.module` finds it by looking beside
# Bundle.main.resourceURL, and nowhere else in a .app would be on that path.
BUNDLE="$(dirname "$BIN")/Flip_Flip.bundle"
[ -d "$BUNDLE" ] && cp -R "$BUNDLE" "$APP/Contents/Resources/"

# No '$' or backticks in the body, so an unquoted heredoc is safe and lets the
# icon keys drop in.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Flip</string>
    <key>CFBundleDisplayName</key>       <string>Flip</string>
    <key>CFBundleExecutable</key>        <string>Flip</string>
    <!-- The original Flip's identifier, taken over when this build replaced
         it, so its settings and saved folder carry across. -->
    <key>CFBundleIdentifier</key>        <string>ai.flip.app</string>
${ICON_KEYS}
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <!-- The newest version in VersionHistory.swift. That file counts it
         off its own list; this one cannot read Swift, so it is repeated here
         and the two have to be changed together. -->
    <key>CFBundleShortVersionString</key><string>0.0.4.1</string>
    <key>CFBundleVersion</key>           <string>0.0.4.1</string>
    <key>LSMinimumSystemVersion</key>    <string>15.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>   <string>Flip Document</string>
            <key>CFBundleTypeRole</key>   <string>Editor</string>
            <key>LSItemContentTypes</key> <array><string>ai.flip.document</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "built $APP"
