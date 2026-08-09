# Linux Packaging Setup Complete

This document summarizes the Linux packaging infrastructure that has been created for ChatNyto.

## What Was Created

A complete automated packaging pipeline for building both Debian and AUR (Arch Linux) packages:

### Scripts in `builds/linux/`

1. **`build-all.sh`** - Master build orchestrator
   - Builds both Debian and AUR packages
   - Usage: `./build-all.sh [version]`

2. **`build-debian.sh`** - Debian (.deb) package builder
   - Creates standard Debian packages
   - Configurable output directory
   - Usage: `./build-debian.sh 1.0.1 .`

3. **`build-aur.sh`** - AUR package structure generator
   - Creates PKGBUILD and .SRCINFO
   - Ready for AUR submission or local builds
   - Usage: `./build-aur.sh 1.0.1`

4. **`verify.sh`** - Verification and validation tool
   - Checks for required tools
   - Validates release bundle
   - Reports build status
   - Usage: `./verify.sh 1.0.1`

### Documentation

1. **`README.md`** - Quick start guide
   - Installation instructions
   - Build examples
   - Troubleshooting

2. **`PACKAGING.md`** - Comprehensive guide
   - Complete build pipeline
   - Directory structure
   - Deployment procedures
   - Maintenance guidelines

## Quick Start

### Prerequisites

Install required tools:

```bash
# Debian/Ubuntu
sudo apt-get install dpkg tar gzip

# Arch Linux
sudo pacman -S dpkg tar gzip base-devel
```

### Building Packages

1. **Verify setup:**
   ```bash
   cd builds/linux
   ./verify.sh 1.0.1
   ```

2. **Build all packages:**
   ```bash
   ./build-all.sh 1.0.1
   ```

3. **Result:**
   - `builds/linux/chatnyto_1.0.1_amd64.deb` - Debian package
   - `builds/arch/chatnyto/` - AUR package structure

### Installing Packages

**Debian/Ubuntu:**
```bash
sudo dpkg -i builds/linux/chatnyto_1.0.1_amd64.deb
sudo apt-get install -f  # Install dependencies
```

**Arch Linux:**
```bash
cd builds/arch/chatnyto
makepkg -si
```

## Directory Structure

```
builds/
├── PACKAGING.md                  # Master documentation
├── linux/                        # Linux build scripts
│   ├── README.md
│   ├── build-all.sh
│   ├── build-debian.sh
│   ├── build-aur.sh
│   ├── verify.sh
│   ├── x86_64/
│   │   └── chatnyto.1.0.1.tar.gz
│   └── chatnyto_*.deb           # Built packages
├── debian/                       # Debian package output
│   └── chatnyto_*.deb
└── arch/                         # AUR package structure
    └── chatnyto/
        ├── PKGBUILD
        └── .SRCINFO
```

## How It Works

### Release Bundle
The Flutter app is built and packaged into a tarball:
```
builds/linux/x86_64/chatnyto.VERSION.tar.gz
```

Contains:
- `build/linux/x64/release/bundle/chatnyto` (executable)
- `lib/` (libraries)
- `data/` (assets)

### Debian Package
The tarball is extracted and reorganized into a standard Debian structure:
- `/opt/chatnyto/` - Application bundle
- `/usr/bin/chatnyto` - Launcher script
- `/usr/share/applications/chatnyto.desktop` - Desktop entry
- `DEBIAN/` - Control files

### AUR Package
A PKGBUILD is generated that:
- References the release bundle
- Defines build steps
- Specifies dependencies
- Creates metadata (.SRCINFO)

## Building for Distribution

### Create a Release

1. **Build Flutter app:**
   ```bash
   cd flutter_app/chatnyto
   flutter build linux --release
   ```

2. **Package the bundle:**
   ```bash
   cd ../../builds/linux
   tar -czf x86_64/chatnyto.1.0.1.tar.gz \
     -C ../../flutter_app/chatnyto/build/linux/x64/release bundle/
   ```

3. **Build packages:**
   ```bash
   ./build-all.sh 1.0.1
   ```

4. **Verify packages:**
   ```bash
   # Test Debian
   sudo dpkg -i chatnyto_1.0.1_amd64.deb
   chatnyto --version
   sudo dpkg -r chatnyto

   # Test AUR
   cd ../arch/chatnyto
   makepkg -si
   chatnyto --version
   ```

5. **Upload:**
   - Debian: Upload to PPA, release repository, or GitHub
   - AUR: Publish to AUR or internal repository

## Dependencies

### Runtime
- **GTK 3** - UI toolkit
- **OpenGL** - Graphics

Debian/Ubuntu: `libgtk-3-0 libgl1-mesa-glx`  
Arch Linux: `gtk3 libgl`

### Build Tools
- **dpkg** - Debian packaging tools
- **tar/gzip** - Archive utilities
- **makepkg** (for AUR) - Arch Linux package builder

## Features

✓ **Automated** - Single command builds both package formats  
✓ **Validated** - Verification script checks integrity  
✓ **Documented** - Comprehensive guides included  
✓ **Standard** - Follows distribution guidelines  
✓ **Flexible** - Individual scripts for custom builds  
✓ **Maintainable** - Clean shell scripts, easy to modify  

## Deployment Strategy

### For Debian/Ubuntu Users
- Publish `.deb` to:
  - Personal PPA (Launchpad)
  - GitHub Releases
  - Organization repository
  - Package repository (Aptly, etc.)

### For Arch Linux Users
- Submit PKGBUILD to:
  - AUR (Arch Linux User Repository)
  - Internal repository
  - Build locally: `makepkg -si`

### For Other Linux Systems
- Provide release bundle tarball
- Users extract and run directly:
  ```bash
  tar -xzf chatnyto-1.0.1-linux-x64.tar.gz
  cd build/linux/x64/release/bundle
  ./chatnyto
  ```

## Next Steps

1. **Review documentation:**
   - Read `builds/linux/README.md` for quick reference
   - Read `builds/PACKAGING.md` for comprehensive guide

2. **Prepare for release:**
   - Update version numbers if needed
   - Rebuild Flutter app for latest features
   - Create release bundle tarball

3. **Test packages:**
   - Run `./verify.sh` to check setup
   - Build with `./build-all.sh`
   - Test installation on target systems

4. **Deploy:**
   - Upload to distribution channels
   - Announce new release
   - Update documentation

## Troubleshooting

### dpkg-deb not found
```bash
sudo apt-get install dpkg
```

### Bundle extraction fails
```bash
# Verify bundle integrity
tar -tzf builds/linux/x86_64/chatnyto.1.0.1.tar.gz | head
```

### Application won't start after installation
```bash
# Check dependencies
ldd /opt/chatnyto/chatnyto

# Install missing libraries
sudo apt-get install libgtk-3-0 libgl1-mesa-glx
```

### AUR build fails
```bash
# Install build dependencies
sudo pacman -S base-devel

# Clean and rebuild
cd builds/arch/chatnyto
makepkg --clean
rm -rf pkg src
makepkg -si
```

## Support

For issues with:
- **Packaging scripts** - Check `builds/linux/README.md`
- **Build process** - See `builds/PACKAGING.md`
- **Application runtime** - Consult application documentation
- **Debian packaging** - https://wiki.debian.org/BuildingAPackage
- **AUR guidelines** - https://wiki.archlinux.org/title/AUR_submission_guidelines

## Version Information

- **Setup Date:** August 9, 2026
- **ChatNyto Version:** 1.0.1
- **Target Systems:** Debian/Ubuntu, Arch Linux, generic Linux
- **Architecture:** x86_64 (amd64)

---

All build scripts are located in `builds/linux/` and are ready to use.
Start with `./verify.sh` to ensure everything is configured correctly.
