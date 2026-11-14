set -eo pipefail
ln -s /Applications "build/dmg_staging/Applications"
DMG_PATH="build/${APP_NAME}-${VERSION}-macOS-arm64.dmg"
hdiutil create \
  -volname "${DISPLAY_NAME}" \
  -srcfolder "build/dmg_staging" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"
ls -lh "${DMG_PATH}"
