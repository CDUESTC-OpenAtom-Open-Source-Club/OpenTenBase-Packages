# libpqxx 7.9.2 Dependencies for OpenTenBase

## Why libpqxx 7.9.2?

OpenTenBase's `opentenbase_ctl` tool requires **libpqxx >= 7.9** due to fixes in `range.hxx` that older versions (7.6.x/7.7.x) lack. However:

- **Ubuntu 24.04 (noble)**: System repo has libpqxx 7.7.x (incompatible)
- **Debian 13 (trixie)**: System repo may not have libpqxx
- **RHEL/EPEL**: EPEL provides libpqxx 7.6.x/7.7.x (incompatible)

## Solution

We pre-build libpqxx 7.9.2 packages and host them on:
- **GitHub Release**: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tag/libpqxx-7.9.2
- **CDN**: https://repo.blackevil217.com/deps/

The `setup-apt.sh` and `setup-rpm.sh` scripts automatically detect and install these dependencies.

## Supported Platforms

### DEB Packages (amd64 + arm64)

| Distro | Codename | amd64 | arm64 |
|--------|----------|-------|-------|
| Ubuntu 20.04 | focal | ✅ | ✅ |
| Ubuntu 22.04 | jammy | ✅ | ✅ |
| Ubuntu 24.04 | noble | ✅ | ✅ |
| Ubuntu 25.04 | plucky | ✅ | ✅ |
| Debian 11 | bullseye | ✅ | ✅ |
| Debian 12 | bookworm | ✅ | ✅ |
| Debian 13 | trixie | ✅ | ✅ |

### RPM Packages (x86_64 + aarch64)

| Distro | x86_64 | aarch64 |
|--------|--------|---------|
| Rocky Linux 8 | ✅ | ✅ |
| Rocky Linux 9 | ✅ | ✅ |
| AlmaLinux 8 | ✅ | ✅ |
| AlmaLinux 9 | ✅ | ✅ |
| Fedora 40 | ✅ | ✅ |
| openEuler 22.03 | ✅ | ✅ |

## Manual Installation

If automatic installation fails, you can manually download and install:

### DEB
```bash
# Download for your distro/arch
curl -LO https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/libpqxx-7.9.2/libpqxx-7.9_7.9.2-1opentenbase1~noble_amd64.deb
curl -LO https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/libpqxx-7.9.2/libpqxx-7.9-dev_7.9.2-1opentenbase1~noble_amd64.deb

# Install
sudo dpkg -i libpqxx-7.9_*.deb libpqxx-7.9-dev_*.deb
```

### RPM
```bash
# Download for your distro/arch
curl -LO https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/libpqxx-7.9.2/libpqxx-7.9.2-1.opentenbase.el9.x86_64.rpm
curl -LO https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/libpqxx-7.9.2/libpqxx-devel-7.9.2-1.opentenbase.el9.x86_64.rpm

# Install
sudo dnf install libpqxx-*.rpm libpqxx-devel-*.rpm
```

## Building from Source

If no pre-built package is available for your platform:

```bash
# Install dependencies
sudo apt install cmake libpq-dev g++  # DEB
sudo dnf install cmake libpq-devel gcc-c++  # RPM

# Build libpqxx 7.9.2
curl -fsSL https://github.com/jtv/libpqxx/archive/refs/tags/7.9.2.tar.gz -o libpqxx.tar.gz
tar xzf libpqxx.tar.gz
cd libpqxx-7.9.2
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_SHARED_LIBS=ON -DSKIP_BUILD_TEST=ON
cmake --build build -j$(nproc)
sudo cmake --install build
sudo ldconfig
```

## Build Workflow

The `.github/workflows/build-libpqxx.yml` workflow automatically builds and releases these packages.

To trigger a rebuild:
1. Go to Actions → Build libpqxx Dependencies
2. Click "Run workflow"
3. Packages will be uploaded to GitHub Release `libpqxx-7.9.2`