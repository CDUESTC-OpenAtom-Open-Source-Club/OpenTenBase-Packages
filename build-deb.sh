#!/bin/bash
# OpenTenBase .deb Build Script
# Usage: ./build-deb.sh [source_dir] [output_dir]

set -e

# Default paths
SOURCE_DIR="${1:-/source}"
OUTPUT_DIR="${2:-/output}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check source directory
check_source() {
    if [ ! -d "$SOURCE_DIR" ]; then
        log_error "Source directory not found: $SOURCE_DIR"
        exit 1
    fi

    if [ ! -f "$SOURCE_DIR/configure" ] && [ ! -f "$SOURCE_DIR/Makefile" ]; then
        log_error "No build files found (configure or Makefile)"
        exit 1
    fi
}

# Install build dependencies
install_dependencies() {
    log_info "Installing build dependencies..."

    apt-get update -qq
    apt-get install -y -qq \
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
        pkg-config \
        libtool

    # Optional packages (may not exist on all distro versions)
    apt-get install -y libpqxx-dev 2>/dev/null || log_warn "libpqxx-dev not available"
    apt-get install -y libcli11-dev 2>/dev/null || log_warn "libcli11-dev not available"

    # Update shared library cache
    ldconfig

    # OpenTenBase's configure hardcodes /usr/local/lib/libzstd.a and /usr/local/lib/liblz4.a
    log_info "Setting up library symlinks for configure..."
    mkdir -p /usr/local/lib

    for f in /usr/lib/x86_64-linux-gnu/libzstd.a /usr/lib/x86_64-linux-gnu/libzstd.so \
             /usr/lib/x86_64-linux-gnu/liblz4.a /usr/lib/x86_64-linux-gnu/liblz4.so; do
        if [ -f "$f" ]; then
            ln -sf "$f" "/usr/local/lib/$(basename $f)"
        fi
    done

    # Ensure -latomic is available for 128-bit atomics
    if [ ! -f /usr/lib/x86_64-linux-gnu/libatomic.so ]; then
        gcc_path=$(gcc -print-file-name=libatomic.so 2>/dev/null)
        if [ -n "$gcc_path" ] && [ -f "$gcc_path" ]; then
            ln -sf "$gcc_path" /usr/lib/x86_64-linux-gnu/libatomic.so
            log_info "Symlinked libatomic.so"
        fi
    fi
}

# Apply patches
apply_patches() {
    log_info "Applying patches..."

    cd "$SOURCE_DIR"

    # Apply bool/stdbool patch
    if [ -f debian/patches/01-bool-stdbool.patch ]; then
        patch -p1 < debian/patches/01-bool-stdbool.patch || true
    fi

    # Apply nolic sharding patch
    if [ -f debian/patches/02-nolic-sharding.patch ]; then
        patch -p1 < debian/patches/02-nolic-sharding.patch || true
    fi

    # Add PQconnectdbParallel to exports.txt if not present
    if [ -f src/interfaces/libpq/exports.txt ]; then
        if ! grep -q "PQconnectdbParallel" src/interfaces/libpq/exports.txt; then
            next_num=$(tail -1 src/interfaces/libpq/exports.txt | awk '{print $2}')
            next_num=$((next_num + 1))
            echo "PQconnectdbParallel  $next_num" >> src/interfaces/libpq/exports.txt
            log_info "Added PQconnectdbParallel to exports.txt (slot $next_num)"
        fi
    fi

    # Remove merge conflict artifact files that might confuse the build
    rm -f src/interfaces/libpq/fe-connect.c.BASE.c \
          src/interfaces/libpq/fe-connect.c.LOCAL.c \
          src/interfaces/libpq/fe-connect.c.REMOTE.c 2>/dev/null || true
}

# Build packages
build_packages() {
    log_info "Building packages..."

    cd "$SOURCE_DIR"

    # Clean previous build
    fakeroot debian/rules clean || true

    # Build packages
    fakeroot debian/rules binary

    # Move to output directory
    mkdir -p "$OUTPUT_DIR"
    mv ../*.deb "$OUTPUT_DIR/"
}

# Verify packages
verify_packages() {
    log_info "Verifying packages..."

    cd "$OUTPUT_DIR"

    for deb in *.deb; do
        echo "=== $deb ==="
        dpkg-deb -I "$deb" | head -15
        echo
    done
}

# Main
main() {
    echo "========================================"
    echo "  OpenTenBase .deb Build Script"
    echo "========================================"
    echo ""

    check_source
    install_dependencies
    apply_patches
    build_packages
    verify_packages

    log_info "Build complete!"
    log_info "Packages: $OUTPUT_DIR"
}

main "$@"
