#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
APP="build/Saimo TV.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

./make_icon.sh >/dev/null
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp abertura/abertura-h.mp4 "$APP/Contents/Resources/abertura-h.mp4"
# Avatares dos perfis (docs/avatares, gerados por scripts/avatares/gerar.py).
mkdir -p "$APP/Contents/Resources/avatares"
cp docs/avatares/png/*.png "$APP/Contents/Resources/avatares/"

swiftc \
  -module-cache-path build/ModuleCache \
  -swift-version 6 \
  -target arm64-apple-macos15.0 \
  -O \
  -framework AVKit \
  -framework MediaPlayer \
  -framework AVFoundation \
  -framework SwiftUI \
  -framework AppKit \
  -framework Metal \
  -framework MetalFX \
  -framework QuartzCore \
  -framework CoreVideo \
  -o "$APP/Contents/MacOS/SaimoTV" \
  Sources/*.swift

# Motor de torrent (SaimoTorrent, Rust): toca fonte de addon sem Debrid.
MOTOR="${SAIMO_TORRENT_DIR:-../SaimoTorrent}/target/aarch64-apple-darwin/release/saimo-torrent"
[ -x "$MOTOR" ] || MOTOR="${SAIMO_TORRENT_DIR:-../SaimoTorrent}/target/release/saimo-torrent"
if [ -x "$MOTOR" ]; then
  cp "$MOTOR" "$APP/Contents/MacOS/saimo-torrent"
else
  echo "aviso: motor de torrent não encontrado (cargo build --release em ../SaimoTorrent)" >&2
fi

codesign --force --sign - --identifier dev.saimo.player "$APP" >/dev/null 2>&1 || true

echo "built: $APP"
