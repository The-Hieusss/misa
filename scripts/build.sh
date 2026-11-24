#!/bin/zsh
# Builds the web UI, then the Swift app, and bundles both into build/M.I.S.A..app
set -e
ROOT="${0:A:h:h}"
OUT="$ROOT/build/M.I.S.A..app"
# The app is put together and signed outside this folder: if it's in iCloud Drive (Desktop or
# Documents syncing), iCloud tags new files a moment after they're written, and codesign refuses
# them ("resource fork, Finder information, or similar detritus") about one build in three.
STAGE="${MISA_STAGE:-$HOME/Library/Caches/app.misa.build}"
APP="$STAGE/M.I.S.A..app"

echo "→ Building web UI"
cd "$ROOT/web"
JS="${MISA_JS:-$(command -v bun >/dev/null && echo bun || echo npm)}"
if [[ ${JS:t} == bun ]]; then
  "$JS" install --frozen-lockfile >/dev/null 2>&1 || "$JS" install
  "$JS" run build
else
  npm install --no-audit --no-fund
  npm run build
fi

echo "→ Building Swift app"
cd "$ROOT/app"
# If the full build fails (an older SDK or toolchain that can't build the on-device AI brain),
# build again without it: she still works, with exact commands only.
FLAGS=()
if ! swift build -c release; then
  echo "⚠ The full build failed. Building again without the AI brain (exact commands still work)."
  FLAGS=(-Xswiftc -DMISA_NO_AI)
  swift build -c release "${FLAGS[@]}"
fi
BIN="$(swift build -c release "${FLAGS[@]}" --show-bin-path)/MISA"

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -X "$BIN" "$APP/Contents/MacOS/MISA"
ditto --noextattr --noqtn "$ROOT/web/dist" "$APP/Contents/Resources/web"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>M.I.S.A.</string>
  <key>CFBundleDisplayName</key><string>M.I.S.A.</string>
  <key>CFBundleIdentifier</key><string>app.misa.assistant</string>
  <key>CFBundleExecutable</key><string>MISA</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>M.I.S.A. reads your calendar when you ask what's on, and adds events you ask for.</string>
  <key>NSCalendarsUsageDescription</key><string>M.I.S.A. reads your calendar when you ask what's on, and adds events you ask for.</string>
  <key>NSRemindersFullAccessUsageDescription</key><string>M.I.S.A. adds and checks off reminders when you ask her to.</string>
  <key>NSRemindersUsageDescription</key><string>M.I.S.A. adds and checks off reminders when you ask her to.</string>
  <key>NSAccessibilityUsageDescription</key><string>M.I.S.A. arranges your windows when you ask her to.</string>
  <key>NSMicrophoneUsageDescription</key><string>M.I.S.A. listens for “Hey MISA” when you turn it on. What you say stays on this Mac.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>M.I.S.A. understands what you say after “Hey MISA”, using speech recognition on this Mac.</string>
  <key>NSBluetoothAlwaysUsageDescription</key><string>M.I.S.A. connects and disconnects your paired Bluetooth devices when you ask her to.</string>
  <key>NSAppleEventsUsageDescription</key><string>M.I.S.A. asks Finder to empty the Trash, and Spotify or Music to play, pause and skip, when you tell her to.</string>
</dict>
</plist>
EOF

# Where she was built from, so she can update herself ("update yourself"): the source folder,
# the commit, and the PATH that found swift and bun/npm (apps launched from Finder get a bare PATH).
PLIST="$APP/Contents/Info.plist"
plutil -replace MISASource -string "$ROOT" "$PLIST"
plutil -replace MISACommit -string "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || true)" "$PLIST"
plutil -replace MISABuildPath -string "$(dirname "$(command -v "$JS" 2>/dev/null || echo /usr/bin/true)"):$PATH" "$PLIST"

# Ad-hoc signature so macOS will run it locally. Clear Finder/extended attributes first:
# codesign refuses a bundle that has picked any up ("resource fork ... detritus not allowed").
xattr -cr "$APP"
codesign --force --sign - "$APP" >/dev/null
codesign --verify --strict "$APP"

# A copy in build/ for running it straight from here (install.sh installs from the signed one).
rm -rf "$OUT"
mkdir -p "${OUT:h}"
ditto --noextattr --noqtn "$APP" "$OUT"
echo "✓ Built $OUT"
