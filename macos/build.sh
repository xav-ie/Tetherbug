#!/usr/bin/env bash
# Builds TetherLink.app from Sources/. Shared by the Nix package, CI and manual builds.
#
#   macos/build.sh <out-dir> [version] [arch...]
#
# With several archs (e.g. arm64 x86_64) the binaries are merged into a universal one. The bundle
# is ad-hoc signed; release signing and notarization happen in CI on top of this.
set -euo pipefail

out=${1:?usage: build.sh <out-dir> [version] [arch...]}
version=${2:-0.0.0-dev}
shift $(($# < 2 ? $# : 2))
archs=("${@:-$(uname -m)}")
here=$(cd "$(dirname "$0")" && pwd)
swiftc=${SWIFTC:-swiftc}
min_macos=14.0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for arch in "${archs[@]}"; do
  "$swiftc" -O -target "$arch-apple-macos$min_macos" "$here"/Sources/*.swift -o "$work/TetherLink-$arch"
done

app="$out/TetherLink.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Library/LaunchAgents"
lipo -create "$work"/TetherLink-* -output "$app/Contents/MacOS/TetherLink"

# App icon, rendered by the binary itself from the generated buddy outline (no raster assets in git).
mkdir -p "$app/Contents/Resources"
"$app/Contents/MacOS/TetherLink" render-icon "$work/AppIcon.iconset"
iconutil -c icns "$work/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>TetherLink</string>
  <key>CFBundleIdentifier</key><string>ie.xav.tetherlink</string>
  <key>CFBundleName</key><string>TetherLink</string>
  <key>CFBundleDisplayName</key><string>TetherLink</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>$min_macos</string>
  <key>NSBluetoothAlwaysUsageDescription</key><string>TetherLink talks to your phone over Bluetooth to turn its hotspot on when your Mac has no Wi-Fi.</string>
</dict></plist>
EOF

# The background agent, registered as a login item by the app (SMAppService).
cat > "$app/Contents/Library/LaunchAgents/ie.xav.tetherlink.agent.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>ie.xav.tetherlink.agent</string>
  <key>BundleProgram</key><string>Contents/MacOS/TetherLink</string>
  <key>ProgramArguments</key><array><string>TetherLink</string><string>agent</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
</dict></plist>
EOF

codesign --force --sign - --identifier ie.xav.tetherlink "$app"
echo "$app"
