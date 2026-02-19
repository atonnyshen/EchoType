#!/bin/bash
# EchoType Build & Package Script
# 用法: ./scripts/build_release.sh

set -e

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$WORKSPACE/helper"
DESKTOP="$WORKSPACE/desktop"
HELPER_BIN="$HELPER/.build/arm64-apple-macosx/release/EchoTypeHelper"

echo "🔨 Building EchoTypeHelper Swift CLI..."
cd "$HELPER"
swift build -c release

echo "✅ EchoTypeHelper built: $HELPER_BIN"

echo "📦 Copying EchoTypeHelper into Tauri externalBin..."
DEST="$DESKTOP/src-tauri/binaries/EchoTypeHelper-aarch64-apple-darwin"
mkdir -p "$DESKTOP/src-tauri/binaries"
cp "$HELPER_BIN" "$DEST"
echo "✅ Binary copied to: $DEST"

echo "🦀 Building Tauri app (cargo tauri build)..."
cd "$DESKTOP"
npm run build
cd src-tauri
export PATH="$HOME/.cargo/bin:$PATH"
cargo tauri build

echo ""
echo "🎉 Build complete!"
echo "   App:  $DESKTOP/src-tauri/target/release/bundle/macos/EchoType.app"
echo "   DMG:  $DESKTOP/src-tauri/target/release/bundle/dmg/EchoType*.dmg"
