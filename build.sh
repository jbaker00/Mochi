#!/bin/bash
# Builds Mochi.app with Xcode, installs it to ~/Applications, then launches it.
set -euo pipefail
cd "$(dirname "$0")"

if command -v xcodegen >/dev/null; then xcodegen generate --quiet; fi

echo "🌱 Building Mochi…"
xcodebuild -project Mochi.xcodeproj -scheme Mochi -configuration Release \
  -derivedDataPath build/DerivedData build -quiet

APP="build/DerivedData/Build/Products/Release/Mochi.app"
mkdir -p "$HOME/Applications"
pkill -x Mochi 2>/dev/null || true
rm -rf "$HOME/Applications/Mochi.app"
cp -R "$APP" "$HOME/Applications/"
echo "✅ Installed to ~/Applications/Mochi.app — launching…"
open "$HOME/Applications/Mochi.app"
