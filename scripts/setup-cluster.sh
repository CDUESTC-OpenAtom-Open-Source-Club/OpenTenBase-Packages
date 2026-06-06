#!/usr/bin/env bash
# =============================================================================
# setup-cluster.sh — OpenTenBase Bootstrap Loader
# =============================================================================
# This is the first-stage script designed to be piped:
#   curl -sSL <url>/setup-cluster.sh | sudo bash
#
# It downloads the full interactive setup script to a temp file and executes
# it from there. This ensures stdin is NOT the pipe when the real script runs,
# so interactive prompts (read) work correctly on ALL terminals and platforms
# (Cloud Studio Web SSH, regular SSH, CI/CD, containers, etc.).
#
# For direct execution (no pipe), you can also run:
#   sudo bash setup-cluster-impl.sh
# =============================================================================

set -euo pipefail

REPO="CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages"
BRANCH="main"
IMPL_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/scripts/setup-cluster-impl.sh"

echo ""
echo "  => Downloading OpenTenBase setup script..."

TMP=$(mktemp /tmp/otb-setup.XXXXXX.sh)
trap 'rm -f "$TMP"' EXIT

# Download with retry
for i in 1 2 3; do
    if curl -sSL --connect-timeout 10 --max-time 60 "${IMPL_URL}" -o "$TMP" 2>/dev/null && [ -s "$TMP" ]; then
        break
    fi
    if [ "$i" -eq 3 ]; then
        echo "  ERROR: Failed to download setup script after 3 attempts."
        echo ""
        echo "  Alternative: download and run directly:"
        echo "    curl -sSL ${IMPL_URL} -o /tmp/setup-cluster.sh"
        echo "    sudo bash /tmp/setup-cluster.sh"
        exit 1
    fi
    echo "  Retry $i/3..."
    sleep 2
done

chmod +x "$TMP"
exec bash "$TMP" "$@"
