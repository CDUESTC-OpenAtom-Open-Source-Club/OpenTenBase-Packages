#!/bin/bash
# OpenTenBase installer — supports Ubuntu 20.04/22.04/24.04, Debian 11/12
# Supports multi-version installation (side-by-side)
# Usage: bash install.sh [--version VERSION] [--build-from-source] [directory]
#   --version VERSION: OpenTenBase version (default: 5.0)
#                      Supported: 5.0, 2.6.0, 2.5.0, master, latest
#   --build-from-source: Build from source instead of downloading packages
#   directory: path to .deb/.rpm files (default: download from GitHub)

set -e

REPO="CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages"
UPSTREAM_REPO="OpenTenBase/OpenTenBase"
DEFAULT_VERSION="5.0"
DEFAULT_TAG="v5.0-multi10"
INSTALL_PREFIX="/usr/lib/opentenbase"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ============================================================
# Cleanup residual /tmp packages from previous runs
# ============================================================
cleanup_residual() {
    # Remove leftover temp download directories from prior install attempts
    if ls -d /tmp/tmp.* >/dev/null 2>&1; then
        for d in /tmp/tmp.*; do
            [ -d "$d" ] || continue
            # Only remove dirs that contain .deb or .rpm files (leftover downloads)
            if ls "$d"/*.deb "$d"/*.rpm 2>/dev/null | head -1 >/dev/null 2>&1; then
                log_info "Cleaning up residual package dir: $d"
                rm -rf "$d"
            fi
        done
    fi
}
cleanup_residual

# Parse arguments
VERSION=""
DIR=""
BUILD_FROM_SOURCE=false
FORCE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --build-from-source)
            BUILD_FROM_SOURCE=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: bash install.sh [--version VERSION] [--build-from-source] [--force] [directory]"
            echo ""
            echo "Options:"
            echo "  --version VERSION       OpenTenBase version (default: $DEFAULT_VERSION)"
            echo "  --build-from-source     Build from source (required for master/latest)"
            echo "  --force                 Force reinstallation even if already installed"
            echo "  directory               Path to .deb/.rpm files"
            echo ""
            echo "Supported versions:"
            echo "  5.0          Stable release (v5.0 tag, 2025-10-22)"
            echo "  2.6.0        Historical release"
            echo "  2.5.0        Historical release"
            echo "  master       Latest development branch (build from source)"
            echo "  latest       Alias for the newest stable tag"
            echo ""
            echo "Examples:"
            echo "  bash install.sh                              # Install v5.0 (stable)"
            echo "  bash install.sh --version 2.6.0              # Install v2.6.0"
            echo "  bash install.sh --version master --build-from-source  # Build & install master"
            echo "  bash install.sh --version latest             # Install latest stable tag"
            echo "  bash install.sh --force                      # Force reinstall v5.0"
            echo "  bash install.sh /path/to/debs                # Install from local directory"
            exit 0
            ;;
        *)
            DIR="$1"
            shift
            ;;
    esac
done

VERSION="${VERSION:-$DEFAULT_VERSION}"

# Resolve "latest" to the newest tag
resolve_latest() {
    log_info "Fetching latest release tag from GitHub..."
    local latest_tag
    latest_tag=$(curl -sL "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || true)
    if [ -z "$latest_tag" ]; then
        # Fallback: get the first tag
        latest_tag=$(curl -sL "https://api.github.com/repos/${UPSTREAM_REPO}/tags" | python3 -c "import sys,json; tags=json.load(sys.stdin); print(tags[0]['name'] if tags else '')" 2>/dev/null || true)
    fi
    if [ -z "$latest_tag" ]; then
        log_error "Could not determine latest version"
        exit 1
    fi
    # Strip leading 'v' for version number
    VERSION="${latest_tag#v}"
    log_info "Latest stable version: $VERSION ($latest_tag)"
}

# Resolve "master" to a version identifier
resolve_master() {
    # Get the short SHA of the latest master commit
    local sha
    sha=$(curl -sL "https://api.github.com/repos/${UPSTREAM_REPO}/commits/master" | python3 -c "import sys,json; print(json.load(sys.stdin)['sha'][:8])" 2>/dev/null || true)
    if [ -z "$sha" ]; then
        log_error "Could not fetch master branch info"
        exit 1
    fi
    VERSION="master-${sha}"
    log_info "Master branch commit: $sha"
}

# Handle special version names
case "$VERSION" in
    latest)
        resolve_latest
        ;;
    master)
        resolve_master
        ;;
esac

# Map version to release tag for pre-built packages
case "$VERSION" in
    5.0)          TAG="v5.0-multi10" ;;
    2.6.0)        TAG="v2.6.0-multi1" ;;
    2.5.0)        TAG="v2.5.0-multi1" ;;
    master-*)     TAG="" ;;  # No pre-built package for master
    *)            TAG="v${VERSION}-multi1" ;;
esac

# Force build-from-source for master
if [[ "$VERSION" == master-* ]]; then
    BUILD_FROM_SOURCE=true
fi

echo "============================================="
echo "  OpenTenBase Installer"
echo "============================================="
echo "  Version:  $VERSION"
echo "  Tag:      ${TAG:-'(source build)'}"
echo "  Source:   $([ "$BUILD_FROM_SOURCE" = true ] && echo "build from source" || echo "pre-built packages")"
echo "  Force:    $([ "$FORCE" = true ] && echo "yes" || echo "no")"
echo "============================================="
echo ""

# Check root
if [ "$(id -u)" -ne 0 ]; then
    log_error "must run as root (sudo bash install.sh)"
    exit 1
fi

# Detect OS version
if [ ! -f /etc/os-release ]; then
    log_error "cannot detect OS version (/etc/os-release not found)"
    exit 1
fi

. /etc/os-release
CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

# Determine package type
case "$ID" in
    ubuntu|debian)  PKG_TYPE="deb" ;;
    centos|rocky|almalinux|fedora|rhel|ol|amzn|openEuler)  PKG_TYPE="rpm" ;;
    *)
        case "$ID_LIKE" in
            *debian*|*ubuntu*)  PKG_TYPE="deb" ;;
            *rhel*|*centos*|*fedora*)  PKG_TYPE="rpm" ;;
            *)  log_error "unsupported distribution: $ID"; exit 1 ;;
        esac
        ;;
esac

log_info "Detected: $ID $VERSION_ID ($CODENAME) — $PKG_TYPE packages"

# ============================================================
# Build from source function
# ============================================================
build_from_source() {
    local src_dir="/tmp/opentenbase-build-$$"
    local otb_version="${VERSION#master-}"
    local build_prefix="${INSTALL_PREFIX}/${otb_version}"

    log_info "Building OpenTenBase from source..."
    log_info "Source will be cloned to: $src_dir"
    log_info "Install prefix: $build_prefix"

    # Install build dependencies
    log_info "Installing build dependencies..."
    if [ "$PKG_TYPE" = "deb" ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq \
            build-essential debhelper fakeroot quilt \
            bison flex perl \
            libreadline-dev zlib1g-dev libssl-dev libpam0g-dev \
            libxml2-dev libldap2-dev uuid-dev \
            libcurl4-openssl-dev liblz4-dev libzstd-dev \
            pkg-config libtool git ca-certificates gcc-12 g++-12
        # Use gcc-12 if available
        if command -v gcc-12 >/dev/null 2>&1; then
            update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100
            update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 100
        fi
    else
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y \
                gcc gcc-c++ make bison flex perl \
                readline-devel zlib-devel openssl-devel pam-devel \
                libxml2-devel openldap-devel libuuid-devel \
                libcurl-devel lz4-devel zstd-devel libssh2-devel \
                pkg-config libtool git
        else
            yum install -y \
                gcc gcc-c++ make bison flex perl \
                readline-devel zlib-devel openssl-devel pam-devel \
                libxml2-devel openldap-devel libuuid-devel \
                libcurl-devel lz4-devel zstd-devel libssh2-devel \
                pkg-config libtool git
        fi
    fi

    # Clone source
    log_info "Cloning OpenTenBase source..."
    if [[ "$VERSION" == master-* ]]; then
        git clone --depth=1 https://github.com/${UPSTREAM_REPO}.git "$src_dir"
    else
        git clone --depth=1 --branch "v${VERSION}" https://github.com/${UPSTREAM_REPO}.git "$src_dir"
    fi

    cd "$src_dir"

    # Apply GCC compatibility patches
    if grep -q 'typedef char bool;' src/include/c.h 2>/dev/null; then
        log_info "Patching c.h: typedef char bool -> typedef _Bool bool"
        sed -i 's/typedef char bool;/typedef _Bool bool;/' src/include/c.h
    fi

    if grep -q 'false, false, NULL' src/gtm/main/gtm_opt.c 2>/dev/null; then
        log_info "Patching gtm_opt.c: fixing struct initializer"
        sed -i '/enable_gtm_resqueue_debug/,/},/{s/true, false, NULL/true, NULL, NULL, false, NULL/; s/false, false, NULL/false, NULL, NULL, false, NULL/}' src/gtm/main/gtm_opt.c
    fi

    # Library path workarounds
    mkdir -p /usr/local/lib
    for lib in libzstd.a liblz4.a; do
        if [ ! -f "/usr/local/lib/$lib" ]; then
            LIB_PATH=$(find /usr -name "$lib" 2>/dev/null | head -1)
            if [ -n "$LIB_PATH" ]; then
                ln -sf "$LIB_PATH" "/usr/local/lib/$lib"
            fi
        fi
    done

    # Architecture flags
    ARCH=$(uname -m)
    CFLAGS="-O2 -g -DNOLIC -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration -Wno-error=int-conversion -Wno-incompatible-pointer-types"
    if [ "$ARCH" = "x86_64" ]; then
        CFLAGS="$CFLAGS -msse4.2 -mcrc32"
    elif [ "$ARCH" = "aarch64" ]; then
        CFLAGS="$CFLAGS -march=armv8-a"
    fi
    export CFLAGS
    export LDFLAGS="-Wl,-rpath,${build_prefix}/lib"

    # Configure
    log_info "Running configure..."
    ./configure \
        --prefix="$build_prefix" \
        --sysconfdir="/etc/opentenbase/${otb_version}" \
        --datadir="$build_prefix/share" \
        --libdir="$build_prefix/lib" \
        --includedir="$build_prefix/include" \
        --enable-user-switch \
        --with-openssl \
        --with-ossp-uuid \
        --with-pam \
        --with-ldap \
        --with-libxml \
        --with-libcurl \
        --with-lz4 \
        --with-zstd

    # Build
    log_info "Building (using $(nproc) cores)..."
    make -j"$(nproc)"

    # Install
    log_info "Installing..."
    make install
    make -C contrib -j"$(nproc)"
    make -C contrib install

    # Create version marker
    echo "$otb_version" > "$build_prefix/VERSION"

    # Install config templates
    local conf_dir="/etc/opentenbase/${otb_version}"
    mkdir -p "$conf_dir"

    # Generate opentenbase.conf
    cat > "$conf_dir/opentenbase.conf" <<CONF
# OpenTenBase configuration — version ${otb_version}
# Built from source on $(date +%Y-%m-%d)

ENABLED_NODES="gtm dn1 coord"

OTB_USER="opentenbase"
OTB_GROUP="opentenbase"
OTB_HOME="$build_prefix"

GTM_PGDATA="/var/lib/opentenbase/${otb_version}/gtm"
GTM_PORT=6666
GTM_LOG="/var/log/opentenbase/${otb_version}/gtm.log"

COORD_PGDATA="/var/lib/opentenbase/${otb_version}/coord"
COORD_PORT=5432
COORD_NODENAME="coord1"
COORD_LOG="/var/log/opentenbase/${otb_version}/coord.log"

DN1_PGDATA="/var/lib/opentenbase/${otb_version}/dn1"
DN1_PORT=15432
DN1_NODENAME="dn001"
DN1_LOG="/var/log/opentenbase/${otb_version}/dn1.log"
COORD_FORWARD_PORT=6669
DN1_FORWARD_PORT=6670
COORD_POOLER_PORT=6667
DN1_POOLER_PORT=6668

START_ORDER="gtm coord dn1"
STOP_ORDER="coord dn1 gtm"
CONF

    # Install opentenbase-ctl if it exists in our repo
    if [ -f "/tmp/OpenTenBase-Packages/config/opentenbase-ctl" ]; then
        install -D -m 0755 "/tmp/OpenTenBase-Packages/config/opentenbase-ctl" /usr/bin/opentenbase-ctl
    fi

    # Install switch-version script
    if [ -f "/tmp/OpenTenBase-Packages/scripts/switch-version.sh" ]; then
        install -D -m 0755 "/tmp/OpenTenBase-Packages/scripts/switch-version.sh" /usr/bin/opentenbase-switch-version
    fi

    # Create versioned data/log directories
    for d in "/var/lib/opentenbase/${otb_version}" \
             "/var/log/opentenbase/${otb_version}" \
             /var/run/opentenbase; do
        mkdir -p "$d"
    done

    # Set up /etc/opentenbase/current symlink
    ln -sf "$conf_dir" /etc/opentenbase/current

    # Create system user if needed
    if ! getent group opentenbase >/dev/null 2>&1; then
        groupadd --system opentenbase 2>/dev/null || true
    fi
    if ! getent passwd opentenbase >/dev/null 2>&1; then
        useradd --system --gid opentenbase --home-dir /var/lib/opentenbase \
            --shell /bin/bash --comment "OpenTenBase administrator" opentenbase 2>/dev/null || true
    fi
    chown opentenbase:opentenbase "/var/lib/opentenbase/${otb_version}"
    chown opentenbase:opentenbase "/var/log/opentenbase/${otb_version}"

    # Cleanup
    log_info "Cleaning up build directory..."
    rm -rf "$src_dir"

    log_info "Build and installation complete!"
}

# ============================================================
# Install pre-built packages
# ============================================================
install_deb() {
    local ver="${VERSION}-1ubuntu1"

    # Determine codename suffix (use tilde ~ per Debian convention)
    local suffix
    case "$CODENAME" in
        noble)    suffix="~noble" ;;
        jammy)    suffix="~jammy" ;;
        focal)    suffix="~focal" ;;
        bookworm) suffix="~bookworm" ;;
        bullseye) suffix="~bullseye" ;;
        bionic)   suffix="~bionic" ;;
        *)        suffix="~$CODENAME" ;;
    esac
    ver="${ver}${suffix}"

    DEBS=(
        "opentenbase_${ver}_all.deb"
        "opentenbase-server_${ver}_amd64.deb"
        "opentenbase-client_${ver}_amd64.deb"
        "opentenbase-contrib_${ver}_amd64.deb"
    )

    # If --force, remove any previously installed version first
    if [ "$FORCE" = true ]; then
        log_info "Force mode: removing any previous OpenTenBase packages..."
        dpkg --purge opentenbase-contrib opentenbase-client opentenbase-server opentenbase 2>/dev/null || true
    fi

    local dir="${DIR:-.}"
    if [ -n "$DIR" ] && [ ! -d "$DIR" ]; then
        log_warn "Directory $DIR does not exist, will download packages"
        dir=""
    fi

    # When a local directory is given, check for matching files there.
    # Otherwise, always download to a fresh temp directory to avoid
    # picking up stale packages from /tmp of a previous run.
    if [ -n "$dir" ] && [ -f "$dir/${DEBS[0]}" ]; then
        cd "$dir"
        log_info "Using local packages from $dir"
    else
        DLDIR=$(mktemp -d)
        log_info "Downloading packages from GitHub (TAG=$TAG)..."
        for deb in "${DEBS[@]}"; do
            echo "  $deb"
            curl -sL -o "${DLDIR}/${deb}" "https://github.com/${REPO}/releases/download/${TAG}/${deb}"
        done
        echo ""
        cd "$DLDIR"
    fi

    local missing=0
    for deb in "${DEBS[@]}"; do
        if [ ! -f "$deb" ]; then
            log_error "$deb not found"
            missing=1
        fi
    done
    [ $missing -eq 1 ] && exit 1

    log_info "Installing packages and dependencies..."
    apt-get update -qq 2>/dev/null || true
    if [ "$FORCE" = true ]; then
        apt-get install -y -qq --reinstall ./*.deb
    else
        apt-get install -y -qq ./*.deb
    fi
}

install_rpm() {
    local ver="${VERSION}.0-1"
    local arch=$(uname -m)

    RPMS=(
        "opentenbase-${ver}.${arch}.rpm"
    )

    # If --force, remove any previously installed version first
    if [ "$FORCE" = true ]; then
        log_info "Force mode: removing any previous OpenTenBase packages..."
        rpm -e opentenbase 2>/dev/null || true
    fi

    local dir="${DIR:-.}"
    if [ -n "$DIR" ] && [ ! -d "$DIR" ]; then
        log_warn "Directory $DIR does not exist, will download packages"
        dir=""
    fi

    if [ -n "$dir" ] && [ -f "$dir/${RPMS[0]}" ]; then
        cd "$dir"
        log_info "Using local packages from $dir"
    else
        DLDIR=$(mktemp -d)
        log_info "Downloading packages from GitHub (TAG=$TAG)..."
        for rpm in "${RPMS[@]}"; do
            echo "  $rpm"
            curl -sL -o "${DLDIR}/${rpm}" "https://github.com/${REPO}/releases/download/${TAG}/${rpm}"
        done
        cd "$DLDIR"
    fi

    log_info "Installing packages..."
    local reinstall_flag=""
    if [ "$FORCE" = true ]; then
        reinstall_flag="--reinstall"
    fi
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y $reinstall_flag ./*.rpm
    elif command -v yum >/dev/null 2>&1; then
        yum install -y $reinstall_flag ./*.rpm
    else
        if [ "$FORCE" = true ]; then
            rpm -ivh --force ./*.rpm
        else
            rpm -ivh ./*.rpm
        fi
    fi
}

# ============================================================
# Main
# ============================================================
if [ "$BUILD_FROM_SOURCE" = true ]; then
    build_from_source
else
    case "$PKG_TYPE" in
        deb) install_deb ;;
        rpm) install_rpm ;;
    esac
fi

echo ""
echo "============================================="
log_info "Installation complete! (v${VERSION})"
echo "============================================="
echo ""
echo "Version management / 版本管理:"
echo "  opentenbase-switch-version              # List installed versions"
echo "  opentenbase-switch-version ${VERSION%%-*}      # Switch to this version"
echo ""
echo "Quick start / 快速开始:"
echo "  opentenbase-ctl init    # Initialize cluster"
echo "  opentenbase-ctl start   # Start all nodes"
echo "  opentenbase-ctl status  # Check status"
echo ""
echo "Connect / 连接:"
echo "  opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres"
