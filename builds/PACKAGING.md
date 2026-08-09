# ChatNyto Linux Packaging Guide

This document explains the complete packaging pipeline for building Debian and AUR packages for ChatNyto.

## Overview

ChatNyto is built as a Flutter application and packaged for Linux distribution through:

1. **Release Bundle** - Built via `flutter build linux --release`
2. **Debian Package** - Standard .deb format for Debian/Ubuntu
3. **AUR Package** - Arch Linux User Repository PKGBUILD

## Directory Structure

```
builds/
├── linux/
│   ├── README.md                 # Linux packaging guide
│   ├── build-all.sh             # Master build script
│   ├── build-debian.sh          # Debian package builder
│   ├── build-aur.sh             # AUR package builder
│   ├── verify.sh                # Verification script
│   ├── x86_64/
│   │   └── chatnyto.VERSION.tar.gz   # Release bundle
│   └── DEPLOYED.txt             # Deployment tracker
├── debian/
│   └── chatnyto_VERSION_amd64.deb    # Built Debian package
├── arch/
│   └── chatnyto/
│       ├── PKGBUILD              # AUR build script
│       └── .SRCINFO              # AUR metadata
└── PACKAGING.md                  # This file
```

## Build Process

### 1. Generate Release Bundle

```bash
cd flutter_app/chatnyto
flutter build linux --release
```

This creates: `build/linux/x64/release/bundle/`

### 2. Package the Bundle

```bash
cd builds/linux
tar -czf x86_64/chatnyto.1.0.1.tar.gz \
  -C flutter_app/chatnyto/build/linux/x64/release bundle/
```

### 3. Build Distribution Packages

```bash
# Verify setup
./verify.sh 1.0.1

# Build both Debian and AUR
./build-all.sh 1.0.1

# Or build individually
./build-debian.sh 1.0.1 .
./build-aur.sh 1.0.1
```

## Package Details

### Debian Package (.deb)

**File:** `chatnyto_VERSION_amd64.deb`

**Contents:**
- `/opt/chatnyto/` - Complete application bundle
- `/usr/bin/chatnyto` - Launcher script
- `/usr/share/applications/chatnyto.desktop` - Desktop entry
- `DEBIAN/control` - Package metadata
- `DEBIAN/postinst` - Post-installation script

**Installation:**
```bash
sudo dpkg -i chatnyto_VERSION_amd64.deb
sudo apt-get install -f  # If dependencies missing
```

**Dependencies:**
- libgtk-3-0 (GTK3 runtime)
- libgl1-mesa-glx (OpenGL)

### AUR Package

**Location:** `../arch/chatnyto/`

**Files:**
- `PKGBUILD` - Build instructions
- `.SRCINFO` - Package metadata

**Building:**
```bash
cd ../arch/chatnyto
makepkg -si
```

**Dependencies:**
- gtk3
- libgl

## Installation on Target Systems

### Debian/Ubuntu

```bash
# Direct installation
sudo dpkg -i chatnyto_1.0.1_amd64.deb

# Or via apt
sudo apt-get update
sudo apt-get install ./chatnyto_1.0.1_amd64.deb
```

### Arch Linux

```bash
# From local PKGBUILD
cd builds/arch/chatnyto
makepkg -si

# Or from AUR (after upload)
git clone https://aur.archlinux.org/chatnyto.git
cd chatnyto
makepkg -si
```

### Other Systems

Use the release bundle directly:
```bash
tar -xzf builds/linux/x86_64/chatnyto.1.0.1.tar.gz
cd build/linux/x64/release/bundle
./chatnyto
```

## Application Launch

After installation, launch ChatNyto via:

```bash
# From command line
chatnyto

# Or from application menu
# (Search for "ChatNyto" in your desktop launcher)
```

## Deployment

### Creating a Release

1. Build the Flutter app:
   ```bash
   flutter build linux --release
   ```

2. Create the tarball:
   ```bash
   cd builds/linux
   tar -czf x86_64/chatnyto.1.0.1.tar.gz \
     -C ../../../flutter_app/chatnyto/build/linux/x64/release bundle/
   ```

3. Build packages:
   ```bash
   ./build-all.sh 1.0.1
   ```

4. Upload packages:
   - Debian: Upload to PPA or GitHub Releases
   - AUR: Submit to Arch Linux AUR

### Testing

Verify packages before distribution:

```bash
# Test Debian package
sudo dpkg -i chatnyto_1.0.1_amd64.deb
chatnyto --version
sudo dpkg -r chatnyto

# Test AUR package
cd arch/chatnyto
makepkg --clean
rm -rf pkg src
makepkg -si
chatnyto --version
```

## Maintenance

### Version Updates

When releasing a new version:

1. Update version in `build-aur.sh` and `build-debian.sh`
2. Rebuild the bundle with Flutter
3. Create new tarball with updated version
4. Run `./build-all.sh VERSION`
5. Test on target systems
6. Upload to distribution channels

### Dependency Changes

If dependencies change:

1. Update `DEBIAN/control` in `build-debian.sh`
2. Update `Depends:` in `PKGBUILD` in `build-aur.sh`
3. Test installation on clean systems
4. Document changes in release notes

## Troubleshooting

### Build Failures

**dpkg-deb not found:**
```bash
sudo apt-get install dpkg
```

**Bundle extraction fails:**
```bash
# Verify tarball integrity
tar -tzf x86_64/chatnyto.VERSION.tar.gz | head
```

**Missing dependencies in .deb:**
```bash
# After installation
sudo apt-get install -f
```

### Runtime Issues

**Application won't start:**
```bash
# Check library dependencies
ldd /opt/chatnyto/chatnyto

# Install missing libraries
sudo apt-get install libgtk-3-0 libgl1-mesa-glx
```

**Desktop entry not appearing:**
```bash
# Rebuild desktop database
sudo update-desktop-database /usr/share/applications
```

## Security Considerations

- All scripts validate bundle integrity before packaging
- Debian packages are created with standard permissions
- AUR packages use upstream source validation
- No build artifacts are committed to version control
- Dependencies are explicitly specified and verified

## Related Documentation

- Flutter Linux Documentation: https://flutter.dev/docs/deployment/linux
- Debian Packaging Guide: https://wiki.debian.org/BuildingAPackage
- AUR Submission Guide: https://wiki.archlinux.org/title/AUR_submission_guidelines

## Version History

- **1.0.1** - Initial Linux packaging setup
  - Debian package support
  - AUR package structure
  - Automated build scripts
