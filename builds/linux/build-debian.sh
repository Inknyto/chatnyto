#!/bin/bash
set -e

# Build Debian package from the release bundle
# Usage: ./build-debian.sh [version] [output-dir]

VERSION="${1:-1.0.1}"
OUTPUT_DIR="${2:-.}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_PATH="${SCRIPT_DIR}/x86_64/chatnyto.${VERSION}.tar.gz"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

if [ ! -f "$BUNDLE_PATH" ]; then
    echo "Error: Bundle not found at $BUNDLE_PATH"
    exit 1
fi

echo "Building Debian package for ChatNyto v${VERSION}..."

# Create base directory structure
cd "$TEMP_DIR"
PKG_DIR="chatnyto_${VERSION}_amd64"
mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/usr/bin"
mkdir -p "$PKG_DIR/usr/share/applications"
mkdir -p "$PKG_DIR/opt/chatnyto"

# Extract bundle to temp location
EXTRACT_DIR=$(mktemp -d)
trap "rm -rf $EXTRACT_DIR" EXIT
tar -xzf "$BUNDLE_PATH" -C "$EXTRACT_DIR"

# Copy bundle files to opt/chatnyto
cp -r "$EXTRACT_DIR/build/linux/x64/release/bundle"/* "$PKG_DIR/opt/chatnyto/" || {
  # If bundle structure is different, try without subdirectories
  cp -r "$EXTRACT_DIR"/* "$PKG_DIR/opt/chatnyto/"
}

# Create wrapper script
cat > "chatnyto_${VERSION}_amd64/usr/bin/chatnyto" << 'EOF'
#!/bin/bash
exec /opt/chatnyto/chatnyto "$@"
EOF
chmod 755 "chatnyto_${VERSION}_amd64/usr/bin/chatnyto"

# Create desktop entry
cat > "chatnyto_${VERSION}_amd64/usr/share/applications/chatnyto.desktop" << 'EOF'
[Desktop Entry]
Name=ChatNyto
Comment=Chat over MQTT, with or without internet
Exec=/usr/bin/chatnyto %U
Icon=chatnyto
Type=Application
Categories=Communication;Network;InstantMessaging;
Terminal=false
MimeType=x-scheme-handler/chatnyto;
EOF

# Create control file
cat > "chatnyto_${VERSION}_amd64/DEBIAN/control" << EOF
Package: chatnyto
Version: ${VERSION}
Architecture: amd64
Maintainer: ChatNyto Team <contact@chatnyto.local>
Homepage: https://github.com/Inknyto/chatnyto
Description: End-to-end encrypted chat over MQTT
 ChatNyto is a decentralized messaging application that works over MQTT
 brokers, with or without internet connectivity. All messages are
 end-to-end encrypted using X25519 and Ed25519 cryptography.
Depends: libgtk-3-0, libgl1-mesa-glx
Section: communication
Priority: optional
EOF

# Create postinst script
cat > "chatnyto_${VERSION}_amd64/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e
update-desktop-database /usr/share/applications || true
exit 0
EOF
chmod 755 "chatnyto_${VERSION}_amd64/DEBIAN/postinst"

# Create prerm script
cat > "chatnyto_${VERSION}_amd64/DEBIAN/prerm" << 'EOF'
#!/bin/bash
set -e
exit 0
EOF
chmod 755 "chatnyto_${VERSION}_amd64/DEBIAN/prerm"

# Build .deb package
dpkg-deb --build "chatnyto_${VERSION}_amd64" "${OUTPUT_DIR}/chatnyto_${VERSION}_amd64.deb"

echo "✓ Built: ${OUTPUT_DIR}/chatnyto_${VERSION}_amd64.deb"
ls -lh "${OUTPUT_DIR}/chatnyto_${VERSION}_amd64.deb"
