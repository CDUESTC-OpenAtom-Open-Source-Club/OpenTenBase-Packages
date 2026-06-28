#!/bin/bash
# OpenTenBase .deb Build Script
# Usage: ./build-deb.sh --source-dir <dir> --version <ver> --codename <name> --output-dir <dir>
# Or legacy: ./build-deb.sh [source_dir] [output_dir]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Default paths
SOURCE_DIR="/source"
OUTPUT_DIR="/output"
VERSION=""
CODENAME=""
OTB_VERSION=""

# Parse arguments (supports both named and positional)
while [[ $# -gt 0 ]]; do
    case $1 in
        --source-dir) SOURCE_DIR="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --codename) CODENAME="$2"; shift 2 ;;
        *)
            # Legacy positional arguments
            if [[ -z "$SOURCE_DIR" || "$SOURCE_DIR" == "/source" ]]; then
                SOURCE_DIR="$1"
            elif [[ -z "$OUTPUT_DIR" || "$OUTPUT_DIR" == "/output" ]]; then
                OUTPUT_DIR="$1"
            fi
            shift
            ;;
    esac
done

# Set OTB_VERSION for debian/rules
if [ -n "$VERSION" ]; then
    OTB_VERSION="$VERSION"
fi

# Detect architecture for library paths
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    LIBDIR="/usr/lib/aarch64-linux-gnu"
else
    LIBDIR="/usr/lib/x86_64-linux-gnu"
fi
log_info "Architecture: $ARCH, Library directory: $LIBDIR"

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
        libatomic1 \
        pkg-config \
        libtool

    # Optional packages (may not exist on all distro versions)
    apt-get install -y libpqxx-dev 2>/dev/null || log_warn "libpqxx-dev not available"
    apt-get install -y libcli11-dev 2>/dev/null || log_warn "libcli11-dev not available"

    # Install CLI11 single-header if libcli11-dev not available (Ubuntu 20.04, Debian 11)
    if [ ! -f /usr/include/CLI/CLI.hpp ]; then
        log_info "Installing CLI11 single-header v2.4.2..."
        apt-get install -y -qq curl 2>/dev/null || true
        mkdir -p /usr/include/CLI
        curl -fsSL https://github.com/CLIUtils/CLI11/releases/download/v2.4.2/CLI11.hpp -o /usr/include/CLI/CLI.hpp
        log_info "CLI11 single-header installed"
    fi

    # Build libpqxx 7.9.2 from source if headers not found
    # (7.6.0 is incompatible with CMake 3.31 — uses removed cmake_determine_compile_features)
    if [ ! -f /usr/include/pqxx/pqxx ]; then
        log_info "Building libpqxx 7.9.2 from source..."
        apt-get install -y -qq libpq-dev cmake curl 2>/dev/null || true
        cd /tmp
        curl -fsSL https://github.com/jtv/libpqxx/archive/refs/tags/7.9.2.tar.gz -o libpqxx.tar.gz
        tar xzf libpqxx.tar.gz
        cd libpqxx-7.9.2
        cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_SHARED_LIBS=ON -DSKIP_BUILD_TEST=ON
        cmake --build build -j$(nproc)
        cmake --install build
        cd /tmp && rm -rf libpqxx*
        ldconfig
        log_info "libpqxx 7.9.2 installed from source"
    fi

    # NOTE: Do NOT remove system libpq.so or libpq-dev.
    # Removing libpq-dev cascades to removing libpqxx-dev (which depends on it),
    # losing the headers needed for opentenbase_ctl. Removing just the .so
    # symlink causes the opentenbase_ctl linker step to fail (-lpq not found).
    # OpenTenBase builds its own internal libpq and links against it directly;
    # the -rpath in LDFLAGS ensures the correct libpq is found at runtime.

    # Update shared library cache
    ldconfig

    # OpenTenBase's configure hardcodes /usr/local/lib/libzstd.a and /usr/local/lib/liblz4.a
    log_info "Setting up library symlinks for configure..."
    mkdir -p /usr/local/lib

    for f in "$LIBDIR/libzstd.a" "$LIBDIR/libzstd.so" \
             "$LIBDIR/liblz4.a" "$LIBDIR/liblz4.so"; do
        if [ -f "$f" ]; then
            ln -sf "$f" "/usr/local/lib/$(basename $f)"
        fi
    done

    # Ensure -latomic is available for 128-bit atomics
    # On Debian, libatomic.so may not exist even with libatomic1 installed.
    log_info "Setting up libatomic for 128-bit atomics..."

    # Install libatomic1 if not present
    apt-get install -y -qq libatomic1 2>/dev/null || true

    # Find and symlink libatomic.so
    if [ ! -f "$LIBDIR/libatomic.so" ]; then
        # Try 1: gcc -print-file-name
        gcc_path=$(gcc -print-file-name=libatomic.so 2>/dev/null)
        if [ -n "$gcc_path" ] && [ -f "$gcc_path" ]; then
            ln -sf "$gcc_path" "$LIBDIR/libatomic.so"
            log_info "Symlinked libatomic.so from gcc path: $gcc_path"
        # Try 2: Symlink from libatomic.so.1
        elif [ -f "$LIBDIR/libatomic.so.1" ]; then
            ln -sf "$LIBDIR/libatomic.so.1" "$LIBDIR/libatomic.so"
            log_info "Symlinked libatomic.so from libatomic.so.1"
        # Try 3: Find it anywhere
        else
            found=$(find /usr/lib -name "libatomic.so*" -type f 2>/dev/null | head -1)
            if [ -n "$found" ]; then
                ln -sf "$found" "$LIBDIR/libatomic.so"
                log_info "Symlinked libatomic.so from: $found"
            else
                log_warn "libatomic.so not found - 128-bit atomics may fail"
            fi
        fi
    fi

    # Verify libatomic.so exists
    if [ -f "$LIBDIR/libatomic.so" ]; then
        log_info "libatomic.so found at: $(readlink -f $LIBDIR/libatomic.so)"
    else
        log_warn "libatomic.so not found - 128-bit atomics patch will handle this"
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

    # Apply 128-bit atomics fix (use __atomic builtins instead of libatomic)
    if [ -f debian/patches/03-atomic128-x86.patch ]; then
        patch -p1 < debian/patches/03-atomic128-x86.patch || true
    fi

    # Remove merge conflict artifact files
    rm -f src/interfaces/libpq/fe-connect.c.BASE.c \
          src/interfaces/libpq/fe-connect.c.LOCAL.c \
          src/interfaces/libpq/fe-connect.c.REMOTE.c 2>/dev/null || true
}

# Build packages
build_packages() {
    log_info "Building packages..."

    cd "$SOURCE_DIR"

    # Copy debian directory from packaging repo if not present
    if [ ! -d "debian" ]; then
        log_error "No debian directory found in source"
        exit 1
    fi

    # Handle version substitution for non-5.0 builds
    if [ -n "$OTB_VERSION" ] && [ "$OTB_VERSION" != "5.0" ]; then
        log_info "Substituting version $OTB_VERSION in debian files..."

        # Replace version in debian/rules
        if [ -f "debian/rules" ]; then
            sed -i "s/^OTB_VERSION := .*/OTB_VERSION := $OTB_VERSION/" debian/rules
        fi

        # Substitute version in debian files
        files=$(find debian/ -type f \( -name '*.install' -o -name '*.dirs' \
          -o -name '*.postinst' -o -name '*.prerm' -o -name '*.postrm' \
          -o -name 'changelog' -o -name 'control' \))
        # 1) versioned install paths: .../opentenbase/5.0/...
        sed -i "s|opentenbase/5\.0/|opentenbase/${OTB_VERSION}/|g" $files
        # 2) OTB_VERSION shell variable in maintainer scripts
        sed -i "s|^OTB_VERSION=\"5\.0\"|OTB_VERSION=\"${OTB_VERSION}\"|" $files
        # 3) changelog version header: opentenbase (5.0-1ubuntu1)
        sed -i "s|^opentenbase (5\.0-|opentenbase (${OTB_VERSION}-|" $files
    fi

    # Clean previous build
    fakeroot debian/rules clean || true

    # Build packages
    fakeroot debian/rules binary

    # Move to output directory
    mkdir -p "$OUTPUT_DIR"
    mv ../*.deb "$OUTPUT_DIR/"

    # Rename packages with codename suffix if provided
    if [ -n "$CODENAME" ]; then
        cd "$OUTPUT_DIR"
        for deb in *.deb; do
            [ -f "$deb" ] || continue
            newname=$(echo "$deb" | sed "s/_${OTB_VERSION:-5.0}-1ubuntu1_/_${OTB_VERSION:-5.0}-1ubuntu1~${CODENAME}_/")
            if [ "$newname" != "$deb" ]; then
                mv "$deb" "$newname"
                log_info "Renamed: $deb -> $newname"
            fi
        done
    fi
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

