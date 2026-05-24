#!/bin/bash
# opentenbase-switch-version — switch between installed OpenTenBase versions
# Usage: opentenbase-switch-version [version]
#   Without arguments: list installed versions and show current
#   With version arg: switch to that version

set -e

CONF_DIR="/etc/opentenbase"
CURRENT_LINK="$CONF_DIR/current"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "must run as root (sudo opentenbase-switch-version)"
        exit 1
    fi
}

# Get list of installed versions
list_versions() {
    local versions=()
    for dir in "$CONF_DIR"/*/; do
        [ -d "$dir" ] || continue
        local ver=$(basename "$dir")
        [ "$ver" = "current" ] && continue
        [ -f "$dir/opentenbase.conf" ] && versions+=("$ver")
    done
    echo "${versions[@]}"
}

# Get current active version
get_current() {
    if [ -L "$CURRENT_LINK" ]; then
        basename "$(readlink -f "$CURRENT_LINK")"
    else
        echo ""
    fi
}

# Show version info
show_version_info() {
    local ver="$1"
    local conf="$CONF_DIR/$ver/opentenbase.conf"
    local current=$(get_current)
    local marker=""

    [ "$ver" = "$current" ] && marker=" ${GREEN}(active)${NC}"

    # Extract key paths from config
    local home=""
    local port=""
    if [ -f "$conf" ]; then
        home=$(grep '^OTB_HOME=' "$conf" | cut -d'"' -f2)
        port=$(grep '^COORD_PORT=' "$conf" | cut -d= -f2 | tr -d ' ')
    fi

    echo -e "  $ver${marker}"
    [ -n "$home" ] && echo "    prefix: $home"
    [ -n "$port" ] && echo "    coord port: $port"
}

# List all installed versions
cmd_list() {
    local versions
    versions=$(list_versions)

    if [ -z "$versions" ]; then
        log_warn "No OpenTenBase versions found in $CONF_DIR"
        exit 0
    fi

    echo "Installed OpenTenBase versions:"
    echo ""
    for ver in $versions; do
        show_version_info "$ver"
    done
    echo ""

    local current=$(get_current)
    if [ -n "$current" ]; then
        log_info "Active version: $current"
    else
        log_warn "No active version set"
    fi
}

# Switch to a specific version
cmd_switch() {
    local target="$1"

    if [ ! -d "$CONF_DIR/$target" ]; then
        log_error "Version $target not found in $CONF_DIR"
        echo "Installed versions: $(list_versions)"
        exit 1
    fi

    if [ ! -f "$CONF_DIR/$target/opentenbase.conf" ]; then
        log_error "No opentenbase.conf found for version $target"
        exit 1
    fi

    local current=$(get_current)
    if [ "$target" = "$current" ]; then
        log_info "Already on version $target"
        return 0
    fi

    # Check if any OpenTenBase server processes are running (postgres, gtm)
    # Use a pattern that won't match the pgrep command itself
    if pgrep -x postgres >/dev/null 2>&1 || pgrep -x gtm >/dev/null 2>&1; then
        log_warn "OpenTenBase server processes are running."
        echo "  opentenbase-ctl stop"
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Switch symlink (use -n to avoid following existing directory symlink)
    ln -sfn "$CONF_DIR/$target" "$CURRENT_LINK"
    log_info "Switched to OpenTenBase $target"

    # Show new config location
    echo ""
    echo "Active config: $CONF_DIR/current/opentenbase.conf"
    echo ""

    # Show port info for awareness
    local port=$(grep '^COORD_PORT=' "$CONF_DIR/$target/opentenbase.conf" | cut -d= -f2 | tr -d ' ')
    [ -n "$port" ] && echo "Coordinator port: $port"

    echo ""
    echo "To initialize and start:"
    echo "  opentenbase-ctl init"
    echo "  opentenbase-ctl start"
}

# Show usage
usage() {
    cat <<EOF
Usage: opentenbase-switch-version [version]

Switch between installed OpenTenBase versions.

Without arguments: list installed versions and show current active version.
With version arg: switch to that version.

Examples:
  opentenbase-switch-version              # List installed versions
  opentenbase-switch-version 5.0          # Switch to v5.0 (stable)
  opentenbase-switch-version 2.6.0        # Switch to v2.6.0
  opentenbase-switch-version master-abc12345  # Switch to master build

Version-specific paths:
  Binaries:  /usr/lib/opentenbase/<version>/
  Config:    /etc/opentenbase/<version>/
  Data:      /var/lib/opentenbase/<version>/
  Logs:      /var/log/opentenbase/<version>/
EOF
}

# Main
case "${1:-}" in
    -h|--help)
        usage
        ;;
    "")
        cmd_list
        ;;
    *)
        check_root
        cmd_switch "$1"
        ;;
esac
