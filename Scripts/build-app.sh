#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift build -c release
app="dist/SpotiRex.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/SpotiRex "$app/Contents/MacOS/SpotiRex"
cp Config/Info.plist "$app/Contents/Info.plist"
cp Assets/SpotiRexIcon.png "$app/Contents/Resources/SpotiRexIcon.png"
iconset=".build/SpotiRex.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" Assets/SpotiRexIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -s format png -z "$double" "$double" Assets/SpotiRexIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/SpotiRex.icns"
codesign --force --sign - --options runtime --entitlements Config/SpotiRex.entitlements "$app"
echo "Built $PWD/$app"
