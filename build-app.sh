#!/bin/bash
# Builds AdwamTally.app from the SwiftPM executable and installs it to a stable
# path so the granted Accessibility permission survives rebuilds.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="AdwamTally"
BUNDLE_ID="com.aminehmida.adwamtally"
VERSION="${VERSION:-1.0}"
# Stable install location keeps the TCC (Accessibility) grant across rebuilds.
# Overridable so CI can assemble the bundle into a staging directory.
INSTALL_DIR="${INSTALL_DIR:-${HOME}/Applications}"
APP="${INSTALL_DIR}/${APP_NAME}.app"

echo "==> Building release binary…"
swift build -c release
BIN=".build/release/${APP_NAME}"
if [[ ! -x "$BIN" ]]; then
  echo "error: built binary not found at $BIN" >&2
  exit 1
fi

echo "==> Assembling ${APP} …"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"

cp "$BIN" "${APP}/Contents/MacOS/${APP_NAME}"

# Bundle the Islamic pattern tile used as the popup background.
if [[ -f "pattern/naqsh.png" ]]; then
  cp "pattern/naqsh.png" "${APP}/Contents/Resources/naqsh.png"
fi

# App icon (misbaha progress-loop logo).
if [[ -f "logos/export/AppIcon.icns" ]]; then
  cp "logos/export/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
fi

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>Adwam Tally</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleExecutable</key>
	<string>${APP_NAME}</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Amine Hmida</string>
</dict>
</plist>
PLIST

echo "==> Code signing…"
# A stable signing identity keeps the app's TCC "designated requirement" the
# same across rebuilds, so the Accessibility grant survives. Run
# ./setup-signing.sh once to create it; otherwise fall back to ad-hoc (grant
# will reset on each rebuild).
SIGN_IDENTITY="AdwamTally Self-Signed"
# Note: no -v — a self-signed identity is "not trusted" for Gatekeeper but is
# perfectly usable for signing, and TCC matches on its stable leaf-cert hash.
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  codesign --force --deep --sign "$SIGN_IDENTITY" --identifier "${BUNDLE_ID}" "$APP"
  echo "    signed with: $SIGN_IDENTITY"
else
  codesign --force --deep --sign - --identifier "${BUNDLE_ID}" "$APP"
  echo "    signed ad-hoc (run ./setup-signing.sh for a grant that survives rebuilds)"
fi

echo ""
echo "Built: ${APP}"
echo "Run:   open \"${APP}\""
echo ""
echo "First launch: grant Accessibility in System Settings ▸ Privacy & Security ▸"
echo "Accessibility, then toggle ${APP_NAME} on (add it with + if missing)."
