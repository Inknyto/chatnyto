#!/bin/bash
set -e

# Build AUR package structure for ChatNyto
# Usage: ./build-aur.sh [version]

VERSION="${1:-1.0.1}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUR_DIR="${SCRIPT_DIR}/../arch/chatnyto"

echo "Building AUR package structure for ChatNyto v${VERSION}..."

mkdir -p "$AUR_DIR"

# Create PKGBUILD
cat > "$AUR_DIR/PKGBUILD" << 'PKGBUILD_EOF'
# Maintainer: ChatNyto Team <contact@chatnyto.local>
pkgname=chatnyto
pkgver=1.0.1
pkgrel=1
pkgdesc="End-to-end encrypted chat over MQTT, with or without internet"
arch=('x86_64')
url="https://github.com/Inknyto/chatnyto"
license=('GPL3')
depends=('gtk3' 'libgl')
makedepends=('tar')
source=("https://github.com/Inknyto/chatnyto/releases/download/v${pkgver}/chatnyto-${pkgver}-linux-x64.tar.gz")
sha256sums=('SKIP')

package() {
  cd "$srcdir"

  # Create necessary directories
  mkdir -p "$pkgdir/opt/chatnyto"
  mkdir -p "$pkgdir/usr/bin"
  mkdir -p "$pkgdir/usr/share/applications"
  mkdir -p "$pkgdir/usr/share/icons/hicolor/256x256/apps"

  # Copy bundle files
  cp -r build/linux/x64/release/bundle/* "$pkgdir/opt/chatnyto/"

  # Create launcher script
  cat > "$pkgdir/usr/bin/chatnyto" << 'EOF'
#!/bin/bash
exec /opt/chatnyto/chatnyto "$@"
EOF
  chmod 755 "$pkgdir/usr/bin/chatnyto"

  # Create desktop entry
  cat > "$pkgdir/usr/share/applications/chatnyto.desktop" << 'EOF'
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
}
PKGBUILD_EOF

# Create .SRCINFO
cat > "$AUR_DIR/.SRCINFO" << 'SRCINFO_EOF'
pkgbase = chatnyto
	pkgdesc = End-to-end encrypted chat over MQTT, with or without internet
	pkgver = 1.0.1
	pkgrel = 1
	url = https://github.com/Inknyto/chatnyto
	arch = x86_64
	license = GPL3
	makedepends = tar
	depends = gtk3
	depends = libgl
	source = https://github.com/Inknyto/chatnyto/releases/download/v1.0.1/chatnyto-1.0.1-linux-x64.tar.gz
	sha256sums = SKIP

pkgname = chatnyto
SRCINFO_EOF

echo "✓ Created AUR package structure in: $AUR_DIR"
echo ""
echo "To build locally:"
echo "  cd $AUR_DIR"
echo "  makepkg -si"
echo ""
echo "To submit to AUR:"
echo "  cd $AUR_DIR"
echo "  git init"
echo "  git add ."
echo "  git commit -m 'Initial commit'"
echo "  # Push to AUR git repository"
