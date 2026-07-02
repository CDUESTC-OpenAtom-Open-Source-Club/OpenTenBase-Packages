#!/bin/bash
# Build libpqxx 7.9.2 DEB packages for multiple distributions
# This script creates libpqxx-7.9 packages for OpenTenBase opentenbase_ctl dependency

set -e

VERSION="7.9.2"
PKG_VERSION="7.9.2-1opentenbase1"

# Supported distributions
DEB_DISTROS=(
    "ubuntu:20.04:focal"
    "ubuntu:22.04:jammy"
    "ubuntu:24.04:noble"
    "ubuntu:25.04:plucky"
    "debian:11:bullseye"
    "debian:12:bookworm"
    "debian:13:trixie"
)

usage() {
    echo "Usage: $0 [--distro <distro>] [--output-dir <dir>] [--all]"
    echo ""
    echo "Options:"
    echo "  --distro       Specific distro to build for (e.g., ubuntu:24.04)"
    echo "  --output-dir   Output directory for packages (default: ./output)"
    echo "  --all          Build for all supported distributions"
    echo ""
    echo "Supported distros:"
    for d in "${DEB_DISTROS[@]}"; do
        echo "  $d"
    done
    exit 1
}

OUTPUT_DIR="./output"
BUILD_ALL=false
TARGET_DISTRO=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --distro)
            TARGET_DISTRO="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --all)
            BUILD_ALL=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

build_for_distro() {
    local container="$1"
    local codename="$2"
    local arch="$3"

    echo "=== Building libpqxx $VERSION for $container ($codename) $arch ==="

    # Build in Docker container
    docker run --rm \
        -v "$(pwd)/debian:/debian:ro" \
        -v "$(pwd)/output:/output" \
        -e VERSION="$VERSION" \
        -e PKG_VERSION="$PKG_VERSION" \
        -e CODENAME="$codename" \
        "$container" bash -c '
            set -e

            export DEBIAN_FRONTEND=noninteractive

            # Install build dependencies
            apt-get update
            apt-get install -y \
                build-essential debhelper fakeroot cmake \
                libpq-dev g++ git curl

            # Download libpqxx source
            cd /tmp
            curl -fsSL https://github.com/jtv/libpqxx/archive/refs/tags/${VERSION}.tar.gz -o libpqxx.tar.gz
            tar xzf libpqxx.tar.gz
            cd libpqxx-${VERSION}

            # Copy debian packaging files
            cp -r /debian ./debian/

            # Update changelog with correct codename
            sed -i "s/unstable/$CODENAME/" debian/changelog

            # Build package
            fakeroot debian/rules binary

            # Move packages to output
            cd /tmp
            for deb in *.deb; do
                [ -f "$deb" ] || continue
                # Add codename suffix
                arch=$(dpkg --print-architecture)
                newname=$(echo "$deb" | sed "s/_${PKG_VERSION}_/_${PKG_VERSION}~${CODENAME}_${arch}_/")
                mv "$deb" "/output/$newname"
                echo "Created: $newname"
            done

            # Cleanup
            rm -rf libpqxx-${VERSION} libpqxx.tar.gz
        '

    echo "=== Completed $container ($codename) ==="
}

if [ "$BUILD_ALL" = true ]; then
    # Build for all distros
    for distro_entry in "${DEB_DISTROS[@]}"; do
        IFS=':' read -r distro ver codename <<< "$distro_entry"
        build_for_distro "${distro}:${ver}" "$codename" "amd64"
    done
elif [ -n "$TARGET_DISTRO" ]; then
    # Build for specific distro
    for distro_entry in "${DEB_DISTROS[@]}"; do
        IFS=':' read -r distro ver codename <<< "$distro_entry"
        if [ "${distro}:${ver}" = "$TARGET_DISTRO" ] || [ "$distro" = "$TARGET_DISTRO" ]; then
            build_for_distro "${distro}:${ver}" "$codename" "amd64"
            break
        fi
    done
else
    # Default: build for current system
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        codename=$(lsb_release -cs 2>/dev/null || echo "unknown")
        build_for_distro "$ID:$VERSION_ID" "$codename" "$(dpkg --print-architecture)"
    else
        echo "Cannot detect current distribution. Use --distro or --all."
        usage
    fi
fi

echo ""
echo "=== All builds completed ==="
echo "Packages in: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"/*.deb 2>/dev/null || echo "No packages found"