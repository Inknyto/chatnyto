#!/bin/bash
set -e

# Build all Linux packages (Debian + AUR)
# Usage: ./build-all.sh [version]

VERSION="${1:-1.0.1}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_TAR="$SCRIPT_DIR/x86_64/chatnyto.${VERSION}.tar.gz"

if [ ! -f "$BUNDLE_TAR" ]; then
    echo "Error: Bundle not found at $BUNDLE_TAR"
    echo "Usage: ./build-all.sh [version]"
    exit 1
fi

echo "Building all Linux packages for ChatNyto v${VERSION}..."
echo ""

# Build Debian package
echo "1. Building Debian package..."
"$SCRIPT_DIR/build-debian.sh" "$VERSION" "$SCRIPT_DIR"

echo ""

# Build AUR package
echo "2. Building AUR package structure..."
"$SCRIPT_DIR/build-aur.sh" "$VERSION"

echo ""
echo "✓ All packages built successfully!"
echo ""
echo "Output files:"
ls -lh "$SCRIPT_DIR"/chatnyto_*.deb 2>/dev/null || echo "  (No .deb files yet)"
echo "  AUR structure: $SCRIPT_DIR/../arch/chatnyto/"
