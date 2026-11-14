set -eo pipefail
APP_BUNDLE="build/dmg_staging/${DISPLAY_NAME}.app"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources/Fonts"

cp "Motif/.build/arm64-apple-macosx/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

if [ -d "Motif/.build/arm64-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle" ]; then
  cp -R "Motif/.build/arm64-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle" "${APP_BUNDLE}/Contents/Resources/"
fi

cp -R Motif/Sources/Motif/Resources/Fonts/* "${APP_BUNDLE}/Contents/Resources/Fonts/" 2>/dev/null || true
cp "build/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

printf "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

DTD_URL="http://www.apple.com/DTDs/PropertyList-1.0.dtd"
cat << EOF | sed 's/^[[:space:]]*//' > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "${DTD_URL}">
<plist version="1.0">
<dict>
<key>CFBundleDevelopmentRegion</key>
<string>en</string>
<key>CFBundleExecutable</key>
<string>${APP_NAME}</string>
<key>CFBundleIconFile</key>
<string>AppIcon</string>
<key>CFBundleIdentifier</key>
<string>${BUNDLE_ID}</string>
<key>CFBundleInfoDictionaryVersion</key>
<string>6.0</string>
<key>CFBundleName</key>
<string>${DISPLAY_NAME}</string>
<key>CFBundleDisplayName</key>
<string>${DISPLAY_NAME}</string>
<key>CFBundlePackageType</key>
<string>APPL</string>
<key>CFBundleShortVersionString</key>
<string>${VERSION}</string>
<key>CFBundleVersion</key>
<string>${BUILD_NUMBER}</string>
<key>LSMinimumSystemVersion</key>
<string>14.0</string>
<key>NSHighResolutionCapable</key>
<true/>
<key>NSPrincipalClass</key>
<string>NSApplication</string>
</dict>
</plist>
EOF

plutil -lint "${APP_BUNDLE}/Contents/Info.plist"
xattr -cr "${APP_BUNDLE}"
codesign --force --deep --sign - "${APP_BUNDLE}"
