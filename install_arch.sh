# ~/Documents/git/chatnyto/install_arch.sh 09 Aug 2026 at 01:23:55 AM
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

