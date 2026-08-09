#!/bin/bash

# Verify packaging requirements and built packages
# Usage: ./verify.sh [version]

VERSION="${1:-1.0.1}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "ChatNyto Linux Packaging Verification"
echo "======================================"
echo ""

# Check tools
echo "Checking required tools..."
TOOLS=("tar" "gzip" "dpkg-deb")
MISSING=()

for tool in "${TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        echo "  ✓ $tool"
    else
        echo "  ✗ $tool (missing)"
        MISSING+=("$tool")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo ""
    echo "Missing tools: ${MISSING[*]}"
    echo "Install with: sudo apt-get install ${MISSING[*]}"
fi

echo ""

# Check bundle
echo "Checking release bundle..."
BUNDLE="$SCRIPT_DIR/x86_64/chatnyto.${VERSION}.tar.gz"
if [ -f "$BUNDLE" ]; then
    SIZE=$(ls -lh "$BUNDLE" | awk '{print $5}')
    echo "  ✓ Found: $BUNDLE ($SIZE)"

    # Verify contents
    if tar -tzf "$BUNDLE" build/linux/x64/release/bundle/chatnyto &>/dev/null; then
        echo "  ✓ Contains executable"
    else
        echo "  ✗ Missing executable in bundle"
    fi
else
    echo "  ✗ Bundle not found: $BUNDLE"
    echo ""
    echo "Build with:"
    echo "  cd flutter_app/chatnyto"
    echo "  flutter build linux --release"
fi

echo ""

# Check output directories
echo "Checking output directories..."
if [ -d "$SCRIPT_DIR/../debian" ]; then
    echo "  ✓ debian/ directory exists"
else
    echo "  ⚠ debian/ directory missing (will be created)"
fi

if [ -d "$SCRIPT_DIR/../arch" ]; then
    echo "  ✓ arch/ directory exists"
else
    echo "  ⚠ arch/ directory missing (will be created)"
fi

echo ""

# Check for existing packages
echo "Checking for built packages..."
DEB_COUNT=$(ls "$SCRIPT_DIR"/chatnyto_*.deb 2>/dev/null | wc -l)
if [ "$DEB_COUNT" -gt 0 ]; then
    echo "  ✓ Found $DEB_COUNT .deb package(s)"
    ls -lh "$SCRIPT_DIR"/chatnyto_*.deb
else
    echo "  (No .deb packages built yet)"
fi

if [ -f "$SCRIPT_DIR/../arch/chatnyto/PKGBUILD" ]; then
    echo "  ✓ Found AUR PKGBUILD"
else
    echo "  (No AUR package structure built yet)"
fi

echo ""
echo "Ready to build! Run:"
echo "  ./build-all.sh $VERSION"
