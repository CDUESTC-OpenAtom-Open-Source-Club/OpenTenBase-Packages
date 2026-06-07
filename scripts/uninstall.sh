#!/usr/bin/env bash
# =============================================================================
# uninstall.sh — OpenTenBase Uninstall Script
# =============================================================================
# Usage:
#   curl -sSL <url>/uninstall.sh | sudo bash
#   sudo bash uninstall.sh              # direct run
#   sudo bash uninstall.sh --purge      # remove data & logs too
#   sudo bash uninstall.sh --yes        # skip all confirmations
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors & helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC} $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
info() { echo -e "  ${BLUE}[INFO]${NC} $*"; }
err()  { echo -e "  ${RED}[ERROR]${NC} $*"; }
step() { echo -e "\n  ${BOLD}>>> $*${NC}"; }

ask_yes_no() {
    local prompt="$1" default="${2:-n}"
    if [[ "$SKIP_CONFIRM" == "true" ]]; then
        return 0
    fi
    local yn_hint="y/N"
    [[ "$default" == "y" ]] && yn_hint="Y/n"
    while true; do
        read -rp "  $prompt [$yn_hint]: " answer
        answer="${answer:-$default}"
        case "$answer" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
PURGE=false
SKIP_CONFIRM=false

for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=true ;;
        --yes|-y) SKIP_CONFIRM=true ;;
        --help|-h)
            echo "Usage: sudo bash uninstall.sh [--purge] [--yes]"
            echo ""
            echo "  --purge    Remove data directory and logs (default: keep)"
            echo "  --yes      Skip all confirmation prompts"
            echo "  --help     Show this help"
            exit 0
            ;;
        *)
            err "Unknown option: $arg"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Detect package manager
# ---------------------------------------------------------------------------
if command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
elif command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
else
    PKG_MGR="unknown"
fi

# ---------------------------------------------------------------------------
# Pre-flight check
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    err "Please run as root: sudo bash uninstall.sh"
    exit 1
fi

echo ""
echo "  ==========================================="
echo "    OpenTenBase Uninstall Script"
echo "  ==========================================="
echo ""

# Check if OpenTenBase is actually installed
INSTALLED=false
if [[ "$PKG_MGR" == "apt" ]] && dpkg -l opentenbase-server &>/dev/null 2>&1; then
    INSTALLED=true
elif [[ "$PKG_MGR" == "dnf" || "$PKG_MGR" == "yum" ]] && rpm -q opentenbase-server &>/dev/null 2>&1; then
    INSTALLED=true
fi

if [[ "$INSTALLED" == "false" ]] && [[ ! -d /var/lib/opentenbase ]] && [[ ! -d /etc/opentenbase ]]; then
    warn "OpenTenBase does not appear to be installed."
    warn "Nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Stop processes
# ---------------------------------------------------------------------------
step "Stopping OpenTenBase processes..."

if pgrep -f "gtm -D" &>/dev/null || pgrep -f "postgres.*opentenbase" &>/dev/null || pgrep -f "opentenbase_ctl" &>/dev/null; then
    # Try graceful stop first
    if command -v opentenbase-ctl &>/dev/null; then
        info "Running opentenbase-ctl stop..."
        opentenbase-ctl stop 2>/dev/null || true
        sleep 2
    fi

    # Kill remaining processes
    pkill -f "gtm -D" 2>/dev/null || true
    pkill -f "postgres.*-D.*opentenbase" 2>/dev/null || true
    pkill -f "opentenbase_ctl" 2>/dev/null || true
    sleep 2

    # Force kill if still running
    if pgrep -f "gtm -D" &>/dev/null || pgrep -f "postgres.*-D.*opentenbase" &>/dev/null; then
        warn "Some processes still running, force killing..."
        pkill -9 -f "gtm -D" 2>/dev/null || true
        pkill -9 -f "postgres.*-D.*opentenbase" 2>/dev/null || true
        pkill -9 -f "opentenbase_ctl" 2>/dev/null || true
        sleep 1
    fi

    ok "All OpenTenBase processes stopped"
else
    ok "No running OpenTenBase processes found"
fi

# ---------------------------------------------------------------------------
# 2. Remove packages
# ---------------------------------------------------------------------------
step "Removing OpenTenBase packages..."

PACKAGES="opentenbase opentenbase-server opentenbase-client opentenbase-contrib libopentenbase-dev opentenbase-dev opentenbase-doc"

if [[ "$PKG_MGR" == "apt" ]]; then
    if dpkg -l opentenbase-server &>/dev/null 2>&1; then
        apt-get remove --purge -y $PACKAGES 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
        ok "DEB packages removed"
    else
        ok "No DEB packages found"
    fi
elif [[ "$PKG_MGR" == "dnf" ]]; then
    if rpm -q opentenbase-server &>/dev/null 2>&1; then
        dnf remove -y $PACKAGES 2>/dev/null || true
        dnf autoremove -y 2>/dev/null || true
        ok "RPM packages removed"
    else
        ok "No RPM packages found"
    fi
elif [[ "$PKG_MGR" == "yum" ]]; then
    if rpm -q opentenbase-server &>/dev/null 2>&1; then
        yum remove -y $PACKAGES 2>/dev/null || true
        ok "RPM packages removed"
    else
        ok "No RPM packages found"
    fi
else
    warn "Unknown package manager, skipping package removal"
fi

# ---------------------------------------------------------------------------
# 3. Remove APT/RPM repo configuration
# ---------------------------------------------------------------------------
step "Removing repository configuration..."

# APT sources
for f in /etc/apt/sources.list.d/opentenbase*.list; do
    if [[ -f "$f" ]]; then
        rm -f "$f"
        ok "Removed $f"
    fi
done

# APT keyring
if [[ -f /usr/share/keyrings/opentenbase-archive-keyring.gpg ]]; then
    rm -f /usr/share/keyrings/opentenbase-archive-keyring.gpg
    ok "Removed GPG keyring"
fi

# RPM repos
for f in /etc/yum.repos.d/opentenbase*.repo; do
    if [[ -f "$f" ]]; then
        rm -f "$f"
        ok "Removed $f"
    fi
done

# RPM GPG key
if rpm -q gpg-pubkey &>/dev/null 2>&1; then
    # Check if our key is installed
    if rpm -q gpg-pubkey 2>/dev/null | grep -i opentenbase &>/dev/null; then
        rpm -e "$(rpm -q gpg-pubkey 2>/dev/null | grep -i opentenbase)" 2>/dev/null || true
        ok "Removed RPM GPG key"
    fi
fi

# Update package index
if [[ "$PKG_MGR" == "apt" ]]; then
    apt-get update &>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 4. Remove config directory
# ---------------------------------------------------------------------------
step "Removing configuration..."

if [[ -d /etc/opentenbase ]]; then
    rm -rf /etc/opentenbase
    ok "Removed /etc/opentenbase"
else
    ok "No config directory found"
fi

# ---------------------------------------------------------------------------
# 5. Remove data and logs (--purge or interactive)
# ---------------------------------------------------------------------------
if [[ "$PURGE" == "true" ]] || ask_yes_no "Remove data directory and logs? (all cluster data will be lost)" "n"; then
    step "Removing data and logs..."

    if [[ -d /var/lib/opentenbase ]]; then
        data_size=$(du -sh /var/lib/opentenbase 2>/dev/null | cut -f1)
        rm -rf /var/lib/opentenbase
        ok "Removed /var/lib/opentenbase (${data_size})"
    fi

    if [[ -d /var/log/opentenbase ]]; then
        rm -rf /var/log/opentenbase
        ok "Removed /var/log/opentenbase"
    fi
else
    info "Data and logs preserved (use --purge to remove)"
fi

# ---------------------------------------------------------------------------
# 6. Remove old binary installations
# ---------------------------------------------------------------------------
step "Checking for legacy installations..."

for old_dir in "/data/opentenbase" "/usr/local/install/opentenbase"; do
    if [[ -d "$old_dir" ]]; then
        dir_size=$(du -sh "$old_dir" 2>/dev/null | cut -f1)
        if ask_yes_no "Remove legacy directory $old_dir (${dir_size})?" "y"; then
            rm -rf "$old_dir"
            ok "Removed $old_dir"
        fi
    fi
done

# ---------------------------------------------------------------------------
# 7. Remove swap files (created by setup script)
# ---------------------------------------------------------------------------
step "Checking for swap files..."

for swapfile in /swapfile /swapfile2; do
    if [[ -f "$swapfile" ]]; then
        if swapon --show 2>/dev/null | grep -q "$swapfile"; then
            if ask_yes_no "Disable and remove swap file $swapfile?" "n"; then
                swapoff "$swapfile" 2>/dev/null || true
                rm -f "$swapfile"
                sed -i "\|${swapfile}|d" /etc/fstab 2>/dev/null || true
                ok "Removed $swapfile"
            fi
        fi
    fi
done

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "  ==========================================="
ok "OpenTenBase has been uninstalled successfully."
echo "  ==========================================="
echo ""
info "If you want to reinstall, run:"
echo "  curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-cluster.sh | sudo bash"
echo ""
