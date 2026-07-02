#!/bin/bash
# OpenTenBase RPM build script
# Usage:
#   bash build-rpm.sh <tarball_path>
#   bash build-rpm.sh --source-dir /path/to/source [--version 5.0]
#
# Builds RPM packages for the current architecture.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARBALL=""
SOURCE_DIR=""
OTB_VERSION="${OTB_VERSION:-5.0}"

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --source-dir)
            SOURCE_DIR="$2"
            shift 2
            ;;
        --version)
            OTB_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage:"
            echo "  bash build-rpm.sh <tarball_path>"
            echo "  bash build-rpm.sh --source-dir /path/to/source [--version 5.0]"
            exit 0
            ;;
        *)
            TARBALL="$1"
            shift
            ;;
    esac
done

# Check rpmbuild
if ! command -v rpmbuild &>/dev/null; then
    err "rpmbuild not installed. Install rpm-build package first."
fi

ARCH=$(uname -m)
RPMBUILD_DIR="$HOME/rpmbuild"

# If --source-dir is given, create a tarball from it
if [ -n "$SOURCE_DIR" ]; then
    if [ ! -d "$SOURCE_DIR" ]; then
        err "Source directory not found: $SOURCE_DIR"
    fi
    TARBALL="/tmp/opentenbase-${OTB_VERSION}-${ARCH}.tar.gz"
    log "Creating tarball from $SOURCE_DIR ..."
    tar czf "$TARBALL" -C "$(dirname "$SOURCE_DIR")" "$(basename "$SOURCE_DIR")"
fi

if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
    err "No tarball provided or file not found."
fi

log "Architecture: $ARCH"
log "Version: $OTB_VERSION"
log "Tarball: $TARBALL"

# Create rpmbuild directory structure
mkdir -p "$RPMBUILD_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Copy tarball with expected name
TARBALL_NAME="opentenbase-${OTB_VERSION}-${ARCH}.tar.gz"
cp "$TARBALL" "$RPMBUILD_DIR/SOURCES/${TARBALL_NAME}"

# Copy additional sources (opentenbase-psql, pg_hba template)
for f in opentenbase-psql pg_hba.conf.template; do
    if [ -f "$SCRIPT_DIR/../config/$f" ]; then
        cp "$SCRIPT_DIR/../config/$f" "$RPMBUILD_DIR/SOURCES/"
    elif [ -f "$SCRIPT_DIR/$f" ]; then
        cp "$SCRIPT_DIR/$f" "$RPMBUILD_DIR/SOURCES/"
    elif [ -f "$f" ]; then
        cp "$f" "$RPMBUILD_DIR/SOURCES/"
    fi
done

# Copy libssh2 source (Source3 in spec - for Rocky 9 compatibility)
# Rocky 9 lacks libssh2, so we bundle it with the package
LIBSSH2_SRC="libssh2-1.11.1.tar.gz"
if [ -f "$SCRIPT_DIR/$LIBSSH2_SRC" ]; then
    cp "$SCRIPT_DIR/$LIBSSH2_SRC" "$RPMBUILD_DIR/SOURCES/"
    log "Copied libssh2 source to SOURCES/"
else
    log "WARNING: libssh2 source not found at $SCRIPT_DIR/$LIBSSH2_SRC"
fi

# Copy spec file and set version
cp "$SCRIPT_DIR/opentenbase.spec" "$RPMBUILD_DIR/SPECS/"

log "Building RPM (this may take a while)..."
rpmbuild -ba --define "otb_version ${OTB_VERSION}" "$RPMBUILD_DIR/SPECS/opentenbase.spec"

log "=========================================="
log "RPM build complete!"
log "=========================================="
log "RPM location: $RPMBUILD_DIR/RPMS/${ARCH}/"
ls -lh "$RPMBUILD_DIR/RPMS/${ARCH}/"*.rpm 2>/dev/null || true
log "=========================================="
