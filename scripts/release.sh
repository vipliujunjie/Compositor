#!/bin/zsh
# Builds a signed, notarized Compositor DMG that opens without warnings on any Mac.
#
# Needs, all kept out of this repository:
#   - a "Developer ID Application" certificate in the login keychain
#   - notarization credentials saved once with:
#       xcrun notarytool store-credentials "compositor-notary" --apple-id "…" --team-id 3E4X3B9Z9T
#   - create-dmg (brew install create-dmg)
# The DMG window background is scripts/dmg/dmg-bg.jpg (600 × 380, the window's exact size) plus
# dmg-bg-retina.jpg (1200 × 760) for Retina displays.
#
# Overrides, for a fork or a build aimed at one audience:
#   TEAM_ID           the signing team (default 3E4X3B9Z9T)
#   NOTARY_PROFILE    the notarytool keychain profile (default compositor-notary)
#   SUFFIX            appended to the shipped app and DMG names (default -zh; empty for upstream)
#   SKIP_NOTARIZATION=1  sign and package only, to check the artifact without a notary round trip
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP=Compositor
TEAM="${TEAM_ID:-3E4X3B9Z9T}"
# A renewed or twice-imported certificate leaves two identities with the same name, which makes
# `codesign --sign "Developer ID Application"` ambiguous. Sign with the fingerprint of the first
# valid Developer ID Application certificate for this team instead.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -v team="(${TEAM})" '/Developer ID Application/ && index($0, team) { print $2; exit }')}"
IDENTITY="${IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-compositor-notary}"
SUFFIX="${SUFFIX:--zh}"
SHIPPED="$APP$SUFFIX"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-}"
# Built outside Dropbox: the extended attributes it adds to files make code signing fail.
WORK="$HOME/Library/Caches/CompositorRelease"
DIST="$PROJECT_DIR/dist"

settings=$(xcodebuild -project "$PROJECT_DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release -showBuildSettings 2>/dev/null)
VERSION=$(print -r -- "$settings" | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}')
BUILD=$(print -r -- "$settings" | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}')
echo "==> $SHIPPED $VERSION ($BUILD), team $TEAM"

rm -rf "$WORK"
mkdir -p "$WORK" "$DIST"
# The export options carry the signing team, so a fork can export with its own certificate without
# editing the checked-in plist.
EXPORT_OPTIONS="$WORK/ExportOptions.plist"
cp "$PROJECT_DIR/scripts/ExportOptions.plist" "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c "Set :teamID $TEAM" "$EXPORT_OPTIONS" >/dev/null

echo "==> Archiving a Release build"
xcodebuild archive -quiet \
  -project "$PROJECT_DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$WORK/$APP.xcarchive" -derivedDataPath "$WORK/DerivedData" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM"

echo "==> Exporting, signed with Developer ID"
xcodebuild -exportArchive -quiet \
  -archivePath "$WORK/$APP.xcarchive" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$WORK/export"
# The shipped name is the exported bundle plus the suffix, so two builds for two audiences are told
# apart on disk and in Finder. The rename happens before notarizing, and the signature and the
# stapled ticket follow the bundle's contents, not its folder name.
APP_PATH="$WORK/export/$SHIPPED.app"
mv "$WORK/export/$APP.app" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [[ -z "$SKIP_NOTARIZATION" ]]; then
  echo "==> Notarizing the app"
  ditto -c -k --keepParent "$APP_PATH" "$WORK/$SHIPPED.zip"
  xcrun notarytool submit "$WORK/$SHIPPED.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
else
  echo "==> Skipping notarization (SKIP_NOTARIZATION is set)"
fi

echo "==> Building the DMG window"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
DMG="$DIST/$APP-$VERSION$SUFFIX.dmg"
rm -f "$DMG"
# Icon centers in the DMG window, in points from its top-left.
APP_X=160
APPLICATIONS_X=440
ICON_Y=180
background=()
LOW="$PROJECT_DIR/scripts/dmg/dmg-bg.jpg"
HIGH="$PROJECT_DIR/scripts/dmg/dmg-bg-retina.jpg"
if [[ -f "$LOW" && -f "$HIGH" ]]; then
  # Finder takes one background file; a TIFF holding both sizes stays sharp on Retina displays.
  sips -s format png -s dpiWidth 72 -s dpiHeight 72 "$LOW" --out "$WORK/background.png" >/dev/null
  sips -s format png -s dpiWidth 144 -s dpiHeight 144 "$HIGH" --out "$WORK/background@2x.png" >/dev/null
  tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null
  background=(--background "$WORK/background.tiff")
elif [[ -f "$LOW" ]]; then
  background=(--background "$LOW")
fi
create-dmg \
  --volname "$SHIPPED" \
  --window-pos 200 120 --window-size 600 380 \
  --icon-size 128 --text-size 13 \
  --icon "$SHIPPED.app" "$APP_X" "$ICON_Y" --hide-extension "$SHIPPED.app" \
  --app-drop-link "$APPLICATIONS_X" "$ICON_Y" \
  "${background[@]}" \
  "$DMG" "$STAGE"

if [[ -z "$SKIP_NOTARIZATION" ]]; then
  echo "==> Signing and notarizing the DMG"
  codesign --sign "$IDENTITY" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"

  echo "==> What Gatekeeper will say on another Mac"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  spctl --assess --type execute --verbose=2 "$APP_PATH"
else
  echo "==> Signing the DMG (not notarized)"
  codesign --sign "$IDENTITY" --timestamp "$DMG"
  echo "    Gatekeeper will warn on another Mac until this DMG is notarized."
fi
echo "==> Done: $DMG"
