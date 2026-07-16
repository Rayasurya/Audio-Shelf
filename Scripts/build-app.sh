#!/bin/zsh
# Assembles the ad-hoc-signed Audio Shelf.app from the SwiftPM build —
# no Xcode required. Usage: zsh Scripts/build-app.sh [--install]
set -euo pipefail

script_directory="${0:A:h}"
package_directory="${script_directory:h}"
cd "${package_directory}"

app_name="Audio Shelf"
bundle_id="com.rayasurya.audioshelf"
version="0.1.0"
dist="${package_directory}/dist"
app="${dist}/${app_name}.app"
contents="${app}/Contents"

echo "→ swift build -c release"
swift build -c release

release_directory=$(swift build -c release --show-bin-path)

echo "→ assembling ${app}"
rm -rf "${app}"
mkdir -p "${contents}/MacOS" "${contents}/Resources"

cp "${release_directory}/AudiobookLibrary" "${contents}/MacOS/AudioShelf"
cp -R "${release_directory}/AudiobookLibrary_AudiobookLibrary.bundle" "${contents}/Resources/"

echo "→ rendering icon"
icon_work=$(mktemp -d)
iconset="${icon_work}/AppIcon.iconset"
mkdir -p "${iconset}"
swift "${script_directory}/make-icon.swift" "${icon_work}/master.png" >/dev/null
for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z ${size} ${size} "${icon_work}/master.png" --out "${iconset}/icon_${size}x${size}.png" >/dev/null
    sips -z ${double} ${double} "${icon_work}/master.png" --out "${iconset}/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "${iconset}" -o "${contents}/Resources/AppIcon.icns"
rm -rf "${icon_work}"

cat > "${contents}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${app_name}</string>
    <key>CFBundleDisplayName</key><string>${app_name}</string>
    <key>CFBundleIdentifier</key><string>${bundle_id}</string>
    <key>CFBundleExecutable</key><string>AudioShelf</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${version}</string>
    <key>CFBundleVersion</key><string>${version}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.books</string>
</dict>
</plist>
PLIST

echo "→ ad-hoc signing"
codesign --force --deep --sign - "${app}"

echo "→ verifying"
codesign --verify --strict "${app}"
plutil -lint "${contents}/Info.plist" >/dev/null

if [[ "${1:-}" == "--install" ]]; then
    echo "→ installing to /Applications"
    rm -rf "/Applications/${app_name}.app"
    cp -R "${app}" "/Applications/${app_name}.app"
    echo "Installed: /Applications/${app_name}.app"
else
    echo "Built: ${app} (pass --install to copy into /Applications)"
fi
