#!/bin/bash
# OpenTenBase v5.0 installer — supports Ubuntu 20.04, 22.04, 24.04
# Usage: bash install.sh [directory]
#   directory: path to .deb files (default: current directory)

set -e

DIR="${1:-.}"
cd "$DIR"

echo "OpenTenBase v5.0 Installer"
echo "========================="

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (sudo bash install.sh)" >&2
    exit 1
fi

# Detect Ubuntu version
if [ ! -f /etc/os-release ]; then
    echo "ERROR: cannot detect OS version (/etc/os-release not found)" >&2
    exit 1
fi

. /etc/os-release
CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

case "$CODENAME" in
    noble)  TAG="ubuntu1" ;;       # 24.04
    jammy)  TAG="1ubuntu1~jammy" ;; # 22.04
    focal)  TAG="1ubuntu1~focal" ;; # 20.04
    *)
        echo "ERROR: unsupported Ubuntu version: $CODENAME" >&2
        echo "Supported: focal (20.04), jammy (22.04), noble (24.04)" >&2
        exit 1
        ;;
esac

echo "Detected: Ubuntu $VERSION_ID ($CODENAME)"

# Package filenames
PREFIX="opentenbase"
VER="5.0"
DEBS=(
    "${PREFIX}_${VER}-${TAG}_all.deb"
    "${PREFIX}-server_${VER}-${TAG}_amd64.deb"
    "${PREFIX}-client_${VER}-${TAG}_amd64.deb"
    "${PREFIX}-contrib_${VER}-${TAG}_amd64.deb"
)

# Check .deb files
missing=0
for deb in "${DEBS[@]}"; do
    if [ ! -f "$deb" ]; then
        echo "ERROR: $deb not found in $DIR" >&2
        echo "Expected files for Ubuntu $CODENAME:" >&2
        printf "  %s\n" "${DEBS[@]}" >&2
        missing=1
    fi
done
[ $missing -eq 1 ] && exit 1

# Install with automatic dependency resolution
echo ">> Installing packages and dependencies..."
apt-get update -qq 2>/dev/null || true
apt-get install -y -qq ./*.deb

echo ""
echo ">> Installation complete!"
echo ""
echo "Quick start:"
echo "  opentenbase-ctl init    # Initialize cluster"
echo "  opentenbase-ctl start   # Start all nodes"
echo "  opentenbase-ctl status  # Check status"
echo ""
echo "Connect:"
echo "  opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres"
