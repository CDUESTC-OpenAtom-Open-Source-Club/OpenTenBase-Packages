# OpenTenBase Official-Grade Package Repository Roadmap

English | [中文](ROADMAP_zh.md)

## Vision

Build a **long-term, stable, cross-distro, future-version-adaptable** "official-grade software packaging/distribution system" for OpenTenBase, like PostgreSQL and Docker, creating a **maintainable, auto-updating, multi-system compatible** package repository.

---

## Long-Term Goals

### Core Objectives

1. **Support Debian / Ubuntu / RPM full series** (15+ distributions, 30+ build targets)
2. **Support multiple OpenTenBase versions coexisting** (v5.0 / v6.0 / development)
3. **Auto-build, auto-sign, auto-publish**, one-command installation for users
4. **Long-term maintainable**, no need to reinvent the wheel when project updates
5. **Comply with Linux distribution standards**, ready to contribute to official

### User Experience Goals

```bash
# User installation (extremely friendly)
curl -sSL https://opentenbase.org/repo/setup.sh | sudo bash
sudo apt install opentenbase

# Or specify version
sudo apt install opentenbase-5.0
```

---

## Technical Architecture

### Overall Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    OpenTenBase Package Repository            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌────────────┐  │
│  │  Ubuntu Repo    │  │  Debian Repo    │  │  RPM Repo  │  │
│  │  18.04-25.04    │  │  9-13           │  │  EL8/9     │  │
│  │  x86_64/arm64   │  │  x86_64/arm64   │  │  Rocky     │  │
│  │  (9 targets)    │  │  (7 targets)    │  │  AlmaLinux │  │
│  └─────────────────┘  └─────────────────┘  │  Fedora    │  │
│                                         │  OpenEuler │  │
│                                         │  (14 tgt)  │  │
│                                         └────────────┘  │
│           │                  │                  │           │
│           └──────────────────┼──────────────────┘           │
│                              │                              │
│                    ┌─────────▼─────────┐                    │
│                    │   GPG Signature   │                    │
│                    └─────────┬─────────┘                    │
│                              │                              │
│                    ┌─────────▼─────────┐                    │
│                    │   Version Manager │                    │
│                    │   (5.0/6.0/dev)   │                    │
│                    └─────────┬─────────┘                    │
│                              │                              │
│                    ┌─────────▼─────────┐                    │
│                    │   CI/CD Pipeline  │                    │
│                    │   (GitHub Actions)│                    │
│                    └───────────────────┘                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
opentenbase-repo/
├── .github/
│   └── workflows/
│       ├── build-deb.yml          # Debian/Ubuntu build
│       ├── build-rpm.yml          # RHEL/CentOS build
│       └── publish-repo.yml       # Publish to repository
├── docker/
│   ├── ubuntu-20.04.Dockerfile    # Ubuntu 20.04 build environment
│   ├── ubuntu-22.04.Dockerfile    # Ubuntu 22.04 build environment
│   ├── ubuntu-24.04.Dockerfile    # Ubuntu 24.04 build environment
│   ├── debian-11.Dockerfile       # Debian 11 build environment
│   └── debian-12.Dockerfile       # Debian 12 build environment
├── scripts/
│   ├── build-deb.sh               # Build script
│   ├── sign-packages.sh           # Signing script
│   └── publish-repo.sh            # Publishing script
├── repo/
│   ├── apt/                       # APT repository
│   │   ├── dists/
│   │   │   ├── focal/             # Ubuntu 20.04
│   │   │   ├── jammy/             # Ubuntu 22.04
│   │   │   ├── noble/             # Ubuntu 24.04
│   │   │   ├── bullseye/          # Debian 11
│   │   │   └── bookworm/          # Debian 12
│   │   └── pool/
│   │       └── main/
│   │           └── o/
│   │               └── opentenbase/
│   └── rpm/                       # RPM repository
│       ├── el8/                   # RHEL/CentOS 8
│       ├── el9/                   # RHEL/CentOS 9
│       └── fedora/                # Fedora
├── docs/
│   ├── installation.md            # Installation guide
│   ├── configuration.md           # Configuration guide
│   └── troubleshooting.md         # Troubleshooting
└── README.md                      # Project description
```

---

## Implementation Path

### Phase 1: Short-term (1–2 weeks) — Lay the Foundation

#### Goals
- Unify build environment with Docker
- Build Ubuntu 18.04-25.04 + Debian 9-13 packages (16 DEB targets)
- Build CentOS Stream 8/9, Rocky Linux 8/9, AlmaLinux 8/9, Fedora 40, OpenEuler 22.03 (14 RPM targets)
- Standardize deb/rpm packaging specifications, support x86_64 + aarch64 dual architectures

#### Task List

- [x] **Create Docker build environments**
  - [x] Ubuntu 20.04 Dockerfile
  - [x] Ubuntu 22.04 Dockerfile (existing)
  - [x] Ubuntu 24.04 Dockerfile (existing)
  - [x] Debian 11 Dockerfile
  - [x] Debian 12 Dockerfile

- [x] **Update CI workflows**
  - [x] Create `.github/workflows/build-multi.yml`
  - [x] Create `.github/workflows/build-multi-optimized.yml`
  - [ ] Test all version builds

- [ ] **Standardize packaging specifications**
  - [ ] Version number specification (follow Debian policy)
  - [ ] Dependency declaration specification
  - [ ] Service file specification
  - [ ] Log path specification
  - [ ] Configuration file specification

- [ ] **Testing and verification**
  - [ ] Ubuntu 20.04 installation test
  - [ ] Ubuntu 22.04 installation test
  - [ ] Ubuntu 24.04 installation test
  - [ ] Debian 11 installation test
  - [ ] Debian 12 installation test

#### Expected Results

- ✅ 16 DEB build targets all successful (Ubuntu 18.04-25.04 + Debian 9-13)
- ✅ 14 RPM build targets all successful (CentOS Stream 8/9 + Rocky 8/9 + AlmaLinux 8/9 + Fedora 40 + OpenEuler 22.03)
- ✅ Support x86_64 + aarch64 dual architectures
- All packages pass lintian/rpmlint checks
- All installation tests pass

---

### Phase 2: Medium-term (1–2 months) — Build Official-Grade APT Repository

#### Goals
- Build APT repository with GPG signing
- One-click installation script
- Multi-version management

#### Task List

- [x] **Build APT repository**
  - [x] Install and configure `reprepro`
  - [x] Create repository directory structure
  - [x] Configure GPG signing
  - [ ] Test repository functionality

- [x] **Create one-click installation script**
  - [x] Detect system version
  - [x] Add GPG key
  - [x] Configure repository source
  - [ ] Install packages

- [x] **Multi-version management**
  - [x] Design version naming convention (versioned prefix + symlink switching)
  - [x] Support multi-version coexistence (/usr/lib/opentenbase/5.0/ versioned paths)
  - [x] Version switching mechanism (opentenbase-switch-version command)

- [x] **Documentation completion**
  - [x] Installation guide (bilingual)
  - [x] Configuration guide
  - [x] Troubleshooting guide

#### Expected Results

- APT repository running normally
- Users can install with one command
- Support multi-version coexistence

---

### Phase 3: Long-term (3–6 months) — Cross-Platform Ecosystem

#### Goals
- RPM package support (RHEL/CentOS/Rocky/Fedora)
- Automated CI/CD pipeline
- Ready to merge into OpenTenBase official repository

#### Task List

- [x] **RPM package support**
  - [x] Create RPM spec files
  - [x] Build RHEL/CentOS 8 packages
  - [x] Build RHEL/CentOS 9 packages
  - [x] Build Fedora packages
  - [x] Build OpenEuler packages

- [x] **Automated CI/CD pipeline**
  - [x] Version release auto-trigger
  - [x] Auto-build all platforms
  - [ ] Auto-sign and publish
  - [ ] Auto-update repository

- [ ] **Official contribution preparation**
  - [ ] Code quality review
  - [ ] Documentation completion
  - [ ] Test coverage improvement
  - [ ] Submit to OpenTenBase official

#### Expected Results

- ✅ Support 15+ distributions (Ubuntu 18.04-25.04, Debian 9-13, CentOS Stream 8/9, Rocky 8/9, AlmaLinux 8/9, Fedora 40, OpenEuler 22.03)
- ✅ Fully automated CI/CD pipeline (30 build targets)
- Ready to contribute to official

---

## Technical Implementation

### Docker Build Environment

#### Ubuntu 20.04 Dockerfile

```dockerfile
FROM ubuntu:20.04

# Set non-interactive mode
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    debhelper \
    devscripts \
    fakeroot \
    quilt \
    bison \
    flex \
    perl \
    libreadline-dev \
    zlib1g-dev \
    libssl-dev \
    libpam0g-dev \
    libxml2-dev \
    libldap2-dev \
    libossp-uuid-dev \
    uuid-dev \
    libcurl4-openssl-dev \
    liblz4-dev \
    libzstd-dev \
    libssh2-1-dev \
    libpqxx-dev \
    libcli11-dev \
    pkg-config \
    libtool \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy build script
COPY scripts/build-deb.sh /build/
RUN chmod +x /build/build-deb.sh

# Default execution
CMD ["/build/build-deb.sh"]
```

### CI Workflow

```yaml
# .github/workflows/build-multi.yml
name: Build Multi-Distro Packages

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - distro: ubuntu
            version: "20.04"
            codename: focal
          - distro: ubuntu
            version: "22.04"
            codename: jammy
          - distro: ubuntu
            version: "24.04"
            codename: noble
          - distro: debian
            version: "11"
            codename: bullseye
          - distro: debian
            version: "12"
            codename: bookworm

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build packages
        run: |
          docker build \
            --file docker/${{ matrix.distro }}-${{ matrix.version }}.Dockerfile \
            --tag opentenbase-builder:${{ matrix.distro }}-${{ matrix.version }} \
            .

          docker run \
            --volume $(pwd)/output:/output \
            opentenbase-builder:${{ matrix.distro }}-${{ matrix.version }}

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: debs-${{ matrix.distro }}-${{ matrix.codename }}
          path: output/*.deb

  publish:
    needs: build
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/')

    steps:
      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: all-debs

      - name: Sign and publish
        run: |
          # Sign and publish to repository
          ./scripts/publish-repo.sh
```

### One-Click Installation Script

```bash
#!/bin/bash
# OpenTenBase one-click installation script
# Usage: curl -sSL https://opentenbase.org/repo/setup.sh | sudo bash

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check root privileges
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Detect system version
detect_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot detect operating system version"
        exit 1
    fi

    . /etc/os-release
    
    case "$ID" in
        ubuntu)
            OS="ubuntu"
            CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
            ;;
        debian)
            OS="debian"
            CODENAME="$VERSION_CODENAME"
            ;;
        *)
            log_error "Unsupported operating system: $ID"
            exit 1
            ;;
    esac

    log_info "Detected: $OS $VERSION_ID ($CODENAME)"
}

# Add GPG key
add_gpg_key() {
    log_info "Adding GPG key..."
    
    curl -fsSL https://opentenbase.org/repo/gpg-key.asc | \
        gpg --dearmor -o /usr/share/keyrings/opentenbase-archive-keyring.gpg
    
    chmod 644 /usr/share/keyrings/opentenbase-archive-keyring.gpg
}

# Configure repository
configure_repo() {
    log_info "Configuring repository..."
    
    echo "deb [signed-by=/usr/share/keyrings/opentenbase-archive-keyring.gpg] \
        https://opentenbase.org/repo/apt $CODENAME main" \
        > /etc/apt/sources.list.d/opentenbase.list
    
    chmod 644 /etc/apt/sources.list.d/opentenbase.list
}

# Install OpenTenBase
install_opentenbase() {
    log_info "Updating package list..."
    apt-get update -qq
    
    log_info "Installing OpenTenBase..."
    apt-get install -y opentenbase
    
    log_info "Installation complete!"
    echo ""
    echo "Quick start:"
    echo "  opentenbase-ctl init    # Initialize cluster"
    echo "  opentenbase-ctl start   # Start all nodes"
    echo "  opentenbase-ctl status  # Check status"
    echo ""
    echo "Connect to database:"
    echo "  opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres"
}

# Main function
main() {
    echo "========================================"
    echo "  OpenTenBase One-Click Installation"
    echo "========================================"
    echo ""
    
    check_root
    detect_os
    add_gpg_key
    configure_repo
    install_opentenbase
}

# Execute main function
main "$@"
```

---

## Successful Case Studies

### PostgreSQL Official Repository

- **Repository URL**: https://apt.postgresql.org/
- **Supported Systems**: Ubuntu 20.04/22.04/24.04 + Debian 11/12
- **Features**: 
  - Each version has independent `.deb` packages
  - Auto-selection via repository
  - GPG signature verification
  - Multi-version coexistence

### Docker Official Repository

- **Repository URL**: https://download.docker.com/
- **Supported Systems**: Ubuntu 20.04/22.04/24.04 + Debian 11/12 + CentOS/RHEL
- **Features**:
  - Unified installation script
  - Auto-detect system version
  - One-click installation

### NodeSource Repository

- **Repository URL**: https://deb.nodesource.com/
- **Supported Systems**: Ubuntu 20.04/22.04/24.04 + Debian 11/12
- **Features**:
  - One-click installation script
  - Auto-configure repository
  - Multi-version management

---

## Maintenance Strategy

### Version Release Process

1. **Code freeze**: Freeze code 1 week before release
2. **Testing verification**: Full platform testing
3. **Version tagging**: Use semantic versioning
4. **Auto-build**: CI auto-triggers build
5. **Sign and publish**: Auto-sign and publish
6. **Update repository**: Auto-update APT/RPM repository

### Security Update Strategy

1. **Security vulnerability response**: Release fix within 24 hours
2. **Auto notification**: Notify users via mailing list
3. **Version rollback**: Support quick rollback to stable version

### Documentation Update Strategy

1. **Synchronous update**: Code and documentation update together
2. **Multi-language support**: Chinese and English bilingual
3. **Versioned documentation**: Each version has independent documentation

---

## Summary

### Solution Advantages

- ✅ **Long-term stable**: Maintainable for 5-10 years
- ✅ **Full platform support**: Debian/Ubuntu full series
- ✅ **Official standard**: Complies with Linux distribution standards
- ✅ **User friendly**: One-click installation
- ✅ **Auto maintenance**: CI/CD automation

### Comparison with Other Solutions

| Solution | Supported Versions | Complexity | User Experience | Long-term Maintenance | Recommendation |
|----------|-------------------|------------|-----------------|----------------------|----------------|
| Expand CI matrix | 3-4 | Low | Medium | Poor | ⭐⭐ |
| Launchpad PPA | Ubuntu only | Medium | High | Medium | ⭐⭐⭐ |
| Docker container | All | Medium | Medium | Medium | ⭐⭐⭐⭐ |
| **Self-built APT repo** | **All** | **High** | **Highest** | **Best** | **⭐⭐⭐⭐⭐** |

### Final Recommendation

**Recommended choice: Self-built APT repository + Docker build**

This is the **standard route for official packaging of open source projects**, and also the **most valuable long-term contribution** you can leave for OpenTenBase.

---

## Current Progress

### Completed ✅

- [x] **Create Docker build environments**
  - [x] Ubuntu 20.04 Dockerfile
  - [x] Ubuntu 22.04 Dockerfile (existing)
  - [x] Ubuntu 24.04 Dockerfile (existing)
  - [x] Debian 11 Dockerfile
  - [x] Debian 12 Dockerfile

- [x] **Update CI workflows**
  - [x] Create `.github/workflows/build-multi.yml`
  - [x] Create `.github/workflows/build-multi-optimized.yml`

- [x] **Documentation completion**
  - [x] Installation guide (bilingual)
  - [x] Configuration guide
  - [x] Troubleshooting guide

- [x] **Toolchain**
  - [x] `test-build.sh` - Local test script
  - [x] `release.sh` - Version release script
  - [x] `build-deb.sh` - Docker build script
  - [x] `setup-apt-repo.sh` - APT repository setup script
  - [x] `sign-packages.sh` - GPG signing script
  - [x] `setup-apt.sh` - One-click installation script

- [x] **Expanded DEB distribution support** — From 5 versions to 16 build targets
  - [x] Ubuntu 18.04 (bionic), 18.10 (cosmic), 19.04 (disco), 19.10 (eoan)
  - [x] Ubuntu 20.04 (focal), 22.04 (jammy), 22.10 (kinetic), 23.10 (mantic)
  - [x] Ubuntu 24.04 (noble), 24.10 (oracular), 25.04 (plucky)
  - [x] Debian 9 (stretch), 10 (buster), 11 (bullseye), 12 (bookworm), 13 (trixie)
  - [x] Support x86_64 + aarch64 dual architectures

- [x] **Expanded RPM distribution support** — From aarch64 only to 14 build targets
  - [x] CentOS Stream 8/9 (x86_64 + aarch64)
  - [x] Rocky Linux 8/9 (x86_64 + aarch64)
  - [x] AlmaLinux 8/9 (x86_64 + aarch64)
  - [x] Fedora 40 (x86_64 + aarch64)
  - [x] OpenEuler 22.03 (x86_64 + aarch64)
  - [x] Added distribution detection: Oracle Linux, Amazon Linux, SUSE (via ID_LIKE compatibility)

- [x] **CI workflow expansion**
  - [x] `.github/workflows/build-deb.yml` — 16 DEB build target matrix
  - [x] `.github/workflows/build-rpm.yml` — 14 RPM build target matrix
  - [x] Total: 30 build targets, covering 15+ distributions

- [x] **Installation script expansion**
  - [x] `scripts/install.sh` — Expanded distribution detection, support all DEB + RPM distributions

- [x] **Testing and verification** — All 16 DEB distributions pass CI smoke tests
- [x] **RPM server verification** — Built and tested on OpenEuler 22.03 aarch64, all components (gtm/coord/dn1) RUNNING
- [x] **Automated CI/CD pipeline** — GitHub Actions auto-build + test + publish
- [x] **Docker Compose multi-node deployment** — Full cluster (GTM + Coordinator + 2 Datanodes) verified
- [x] **Distributed query testing** — INSERT/SELECT/UPDATE/DELETE/RETURNING all passed
- [x] **Source-compiled Docker Compose** — Developers can compile from source with one command
  - [x] GCC 12 compatibility fix (`typedef _Bool bool;` replacing `typedef char bool;`)
  - [x] `gtm_opt.c` struct initialization fix
  - [x] lz4/zstd library path auto-fix
  - [x] Flex `lex.backup` race condition fix (parallel build on Ubuntu 25.04/Debian 13/Fedora 40)
  - [x] `libatomic` linkage fix for 128-bit atomics (`-Wl,--no-as-needed -latomic`)
  - [x] `-mcx16` x86_64-only flag conditional (aarch64 compatibility)
  - [x] Build verified: `postgres (PostgreSQL) 10.0 @ OpenTenBase_v5.0`
  - [x] 38 binaries + all contrib extensions installed successfully
- [x] **ARM64 server deployment verification** — Full cluster test on Huawei Cloud EulerOS 2.0 aarch64
  - [x] GTM + Coordinator + Datanode all running
  - [x] Node group creation and sharding map initialization
  - [x] Distributed tables (SHARD + REPLICATION) working
  - [x] INSERT/SELECT/UPDATE/DELETE/JOIN/INDEX all verified
  - [x] All 15 CI targets passing (7 DEB + 8 RPM)

### In Progress 🔄

- [ ] **Standardize packaging specifications**
  - [ ] Version number specification (follow Debian/RPM policy)
  - [ ] Dependency declaration specification
  - [ ] Service file specification
  - [ ] Log path specification
  - [ ] Configuration file specification

- [ ] **Build APT/RPM repository** (requires domain and server)
- [ ] **Complete testing for all 30 build targets**
- [x] **Auto-release workflow** — tag triggers auto-build + test + release notes + publish
  - [x] `scripts/generate-release-notes.sh` — Auto-generate standardized release notes
  - [x] `.github/workflows/release.yml` — Auto-release workflow
- [ ] **Auto-sign and publish** — GPG signing integration into CI pipeline
- [x] **Multi-version management** — Support v5.0/v6.0/dev version coexistence
  - [x] Versioned install prefix `/usr/lib/opentenbase/5.0/`
  - [x] Versioned config `/etc/opentenbase/5.0/`
  - [x] Symlink-based version switching `/etc/opentenbase/current`
  - [x] `opentenbase-switch-version` version switching command
  - [x] `docs/VERSION-MANAGEMENT.md` multi-version management docs

---

## Required Resources

### Immediately Needed

1. **Test servers** (optional)
   - For testing installation in real environments
   - Suggested: Ubuntu 20.04/22.04/24.04 + Debian 11/12 + CentOS Stream 9 + Rocky Linux 9 + Fedora 40 + OpenEuler 22.03, one each
   - Can use cloud servers (e.g., AWS, Alibaba Cloud, Tencent Cloud)

2. **GitHub Actions quota**
   - Currently using GitHub free quota
   - 2000 minutes free build time per month
   - Consider upgrading to GitHub Pro if more is needed

### Medium-term Needed

3. **Domain name** (optional)
   - For building APT repository
   - Example: `apt.opentenbase.org`
   - Can use GitHub Pages as temporary solution

4. **GPG key**
   - For signing packages
   - Increase user trust

### Long-term Needed

5. **Cloud server**
   - For hosting APT/RPM repository
   - Suggested: At least 2 cores, 4GB RAM
   - Bandwidth: At least 10Mbps

---

**Document Version**: 1.6
**Last Updated**: 2026-05-24
**Latest Changes**: RPM packages fully working — from-source build, server verified on OpenEuler 22.03 aarch64 (gtm/coord/dn1 all RUNNING)
**Maintainer**: muzimu217

---

## Distribution Support Matrix

### DEB Package Support (16 Build Targets)

| Distribution | Version | Codename | x86_64 | aarch64 | Status |
|--------------|---------|----------|--------|---------|--------|
| Ubuntu | 18.04 | bionic | ✅ | - | ✅ |
| Ubuntu | 18.10 | cosmic | ✅ | - | ✅ |
| Ubuntu | 19.04 | disco | ✅ | - | ✅ |
| Ubuntu | 19.10 | eoan | ✅ | - | ✅ |
| Ubuntu | 20.04 | focal | ✅ | ✅ | ✅ |
| Ubuntu | 22.04 | jammy | ✅ | ✅ | ✅ |
| Ubuntu | 22.10 | kinetic | ✅ | - | ✅ |
| Ubuntu | 23.10 | mantic | ✅ | - | ✅ |
| Ubuntu | 24.04 | noble | ✅ | ✅ | ✅ |
| Ubuntu | 24.10 | oracular | ✅ | - | ✅ |
| Ubuntu | 25.04 | plucky | ✅ | ✅ | ✅ |
| Debian | 9 | stretch | ✅ | - | ✅ |
| Debian | 10 | buster | ✅ | - | ✅ |
| Debian | 11 | bullseye | ✅ | ✅ | ✅ |
| Debian | 12 | bookworm | ✅ | ✅ | ✅ |
| Debian | 13 | trixie | ✅ | ✅ | ✅ |

### RPM Package Support (14 Build Targets)

| Distribution | Version | x86_64 | aarch64 | Status |
|--------------|---------|--------|---------|--------|
| CentOS Stream | 8 | ✅ | - | ✅ |
| CentOS Stream | 9 | ✅ | ✅ | ✅ |
| Rocky Linux | 8 | ✅ | - | ✅ |
| Rocky Linux | 9 | ✅ | ✅ | ✅ |
| AlmaLinux | 8 | ✅ | - | ✅ |
| AlmaLinux | 9 | ✅ | ✅ | ✅ |
| Fedora | 40 | ✅ | ✅ | ✅ |
| OpenEuler | 22.03 | ✅ | ✅ | ✅ |

**Total**: 30 build targets, covering 15+ distributions, supporting x86_64 + aarch64 dual architectures
