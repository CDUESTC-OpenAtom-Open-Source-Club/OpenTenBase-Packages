#!/usr/bin/env bash
# =============================================================================
# setup-cluster.sh — OpenTenBase Interactive One-Click Deployment
# =============================================================================
# Usage:
#   curl -sSL <url>/setup-cluster.sh | sudo bash       # interactive (auto-reconnects tty)
#   sudo bash setup-cluster.sh                          # interactive mode
#
# This script handles the full deployment lifecycle:
#   1. Detect OS
#   2. Clean up old installations
#   3. Configure package repository
#   4. Install OpenTenBase packages
#   5. Interactive cluster configuration
#   6. Initialize and start the cluster
#   7. Verify deployment
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Interactive mode setup.
# This script is executed from a temp file (by the bootstrap loader), so
# stdin is safe to redirect — bash reads the script from the file, not fd 0.
# If stdin is not a terminal (e.g. parent was piped), try reconnecting to
# /dev/tty so interactive prompts can receive user input.
# If /dev/tty is unavailable (CI/CD, non-interactive SSH), falls back to
# non-interactive mode using default values.
# ---------------------------------------------------------------------------
if [[ ! -t 0 ]] && [[ -c /dev/tty ]]; then
    if ( : <>/dev/tty ) 2>/dev/null; then
        exec 0</dev/tty
    fi
fi

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
DEFAULT_VERSION="5.0"
for arg in "$@"; do
    case "$arg" in
        --version=*) DEFAULT_VERSION="${arg#*=}" ;;
        --version)   ;; # next arg handled below
        5.0|2.6.0|2.5.0) DEFAULT_VERSION="$arg" ;;
    esac
done
# Handle "--version VALUE" (space-separated)
prev=""
for arg in "$@"; do
    if [[ "$prev" == "--version" ]]; then DEFAULT_VERSION="$arg"; fi
    prev="$arg"
done

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
OT_BASE="/usr/lib/opentenbase"
OT_SYSCONF="/etc/opentenbase"
OT_DATA="/var/lib/opentenbase"
OT_LOG="/var/log/opentenbase"

# Default ports
DEFAULT_GTM_PORT=6666
DEFAULT_COORD_PORT=5432
DEFAULT_COORD_POOLER_PORT=6667
DEFAULT_COORD_FORWARD_PORT=6669
DEFAULT_DN_PORT=15432
DEFAULT_DN_POOLER_PORT=6668
DEFAULT_DN_FORWARD_PORT=6670

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }

# Interactive mode detection (false when piped)
INTERACTIVE=true
if [[ ! -t 0 ]]; then
    INTERACTIVE=false
fi

ask() {
    local prompt="$1"
    local default="${2:-}"
    local answer
    if [[ "$INTERACTIVE" == "true" ]]; then
        if [[ -n "$default" ]]; then
            read -rp "$(echo -e "${CYAN}${prompt} [${default}]:${NC} ")" answer
        else
            read -rp "$(echo -e "${CYAN}${prompt}:${NC} ")" answer
        fi
        echo "${answer:-$default}"
    else
        echo "$default"
    fi
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local answer
    if [[ "$INTERACTIVE" == "true" ]]; then
        read -rp "$(echo -e "${CYAN}${prompt} [${default}]:${NC} ")" answer
        answer="${answer:-$default}"
        [[ "$answer" =~ ^[Yy] ]]
    else
        [[ "$default" =~ ^[Yy] ]]
    fi
}

# ---------------------------------------------------------------------------
# Step 1: Check root
# ---------------------------------------------------------------------------
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "This script requires root privileges"
        echo "Run: sudo bash $0"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Step 1.5: Pre-flight environment checks
# ---------------------------------------------------------------------------
preflight_check() {
    log_step "Running pre-flight environment checks..."

    local issues_found=0

    # Check 1: Broken third-party package sources
    if [[ "$PKG_MGR" == "apt" ]]; then
        check_broken_apt_sources
    fi

    # Check 2: Memory
    check_memory

    # Check 3: Disk space (need at least 2GB free)
    check_disk_space

    if [[ "$issues_found" -gt 0 ]]; then
        echo ""
        log_warn "Pre-flight detected ${issues_found} issue(s). Review above before continuing."
        if ! ask_yes_no "Continue with deployment?" "y"; then
            echo "Aborted."
            exit 1
        fi
    fi
}

check_broken_apt_sources() {
    # Test apt-get update to find broken third-party sources
    local update_output
    update_output=$(apt-get update 2>&1) || true

    # Find sources with "no longer has a Release file" or 404 errors
    local broken_sources
    broken_sources=$(echo "$update_output" | grep -oP '(?<=Err:)\d+\s+\Khttps?://[^\s]+' || true)
    broken_sources+=$'\n'
    broken_sources+=$(echo "$update_output" | grep -oP "The repository '([^']+)' no longer has a Release file" | grep -oP "(?<=')[^']+(?=')" || true)

    if [[ -z "$broken_sources" ]]; then
        log_ok "No broken APT sources detected"
        return 0
    fi

    # Map broken URLs back to source files
    local broken_files=()
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        local src_file
        src_file=$(grep -rl "$url" /etc/apt/sources.list.d/ 2>/dev/null | head -1 || true)
        if [[ -n "$src_file" ]]; then
            broken_files+=("$src_file")
        fi
    done <<< "$broken_sources"

    if [[ ${#broken_files[@]} -eq 0 ]]; then
        return 0
    fi

    issues_found=$((issues_found + 1))
    echo ""
    log_warn "Found ${#broken_files[@]} broken third-party APT source(s):"
    for f in "${broken_files[@]}"; do
        echo -e "  ${YELLOW}• ${f}${NC}"
    done
    log_info "These are NOT OpenTenBase sources — they are pre-existing broken sources"
    log_info "that will prevent 'apt-get update' from succeeding."
    echo ""

    if ask_yes_no "Disable broken sources? (recommended — they will be renamed to .disabled)" "y"; then
        for f in "${broken_files[@]}"; do
            mv "$f" "${f}.disabled" 2>/dev/null && \
                log_ok "Disabled: ${f} → ${f}.disabled" || \
                log_warn "Could not disable: ${f}"
        done
        log_info "Re-running apt-get update..."
        apt-get update -qq 2>/dev/null || log_warn "apt-get update still has warnings"
        log_ok "Broken sources disabled"
    else
        log_warn "Continuing with broken sources — 'apt install' may fail"
    fi
}

check_disk_space() {
    local free_gb
    free_gb=$(df -BG / 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ -n "$free_gb" ]] && [[ "$free_gb" -lt 2 ]]; then
        issues_found=$((issues_found + 1))
        log_error "Insufficient disk space: ${free_gb}GB free. OpenTenBase needs at least 2GB."
    else
        log_ok "Disk space: ${free_gb:-?}GB free"
    fi
}

check_memory() {
    local avail_ram_mb
    avail_ram_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
    if [[ "$avail_ram_mb" -eq 0 ]]; then
        log_warn "Cannot detect RAM, skipping memory check"
        return 0
    fi
    echo -e "  Detected: ${CYAN}${avail_ram_mb}MB${NC} RAM"

    local choice

    if [[ "$avail_ram_mb" -lt 2000 ]]; then
        # --- Tier 1: <2GB — cannot run OpenTenBase at all ---
        issues_found=$((issues_found + 1))
        log_error "Insufficient RAM (${avail_ram_mb}MB). OpenTenBase needs at least 4GB."
        echo ""
        echo -e "  ${RED}OpenTenBase cannot run on this server.${NC}"
        echo -e "  ${YELLOW}Even single-node mode requires ~4GB shared memory for the Coordinator.${NC}"
        echo ""
        echo -e "  Options:"
        echo -e "    • Use a server with 4GB+ RAM"
        echo -e "    • Upgrade this server's memory allocation"
        echo ""
        echo "Aborted."
        exit 1

    elif [[ "$avail_ram_mb" -lt 3000 ]]; then
        # --- Tier 2: 2-3GB — check if container ---
        local is_container=false
        if [[ -f /.dockerenv ]] || grep -qE '(docker|lxc|kubepods)' /proc/1/cgroup 2>/dev/null; then
            is_container=true
        fi

        if [[ "$is_container" == "true" ]]; then
            # Container: no swapon, no swap — can't get enough memory
            issues_found=$((issues_found + 1))
            log_error "Container detected with ${avail_ram_mb}MB RAM."
            echo ""
            echo -e "  ${RED}OpenTenBase Coordinator needs ~4GB shared memory.${NC}"
            echo -e "  ${YELLOW}Containers cannot add swap and have a hard memory limit.${NC}"
            echo ""
            echo -e "  Options:"
            echo -e "    • Increase container memory to 4GB+"
            echo -e "    • Use a real VM instead of a container"
            echo ""
            echo "Aborted."
            exit 1
        fi

        # Real VM: can add swap
        issues_found=$((issues_found + 1))
        log_error "RAM ${avail_ram_mb}MB is below recommended minimum (4GB)."
        echo ""
        echo -e "  ${CYAN}How would you like to proceed?${NC}"
        echo -e "  ${GREEN}1)${NC} Single-node mode with auto swap (recommended)"
        echo -e "  ${GREEN}2)${NC} Add 2G swap and continue with cluster mode"
        echo -e "  ${GREEN}3)${NC} Continue with cluster mode anyway (not recommended)"
        echo -e "  ${GREEN}4)${NC} Abort"
        echo ""
        choice=$(ask "Your choice" "1")
        case "$choice" in
            1)
                log_info "Switching to single-node mode..."
                deploy_single_node
                exit 0
                ;;
            2)
                log_info "Adding 2G swap file..."
                if fallocate -l 2G /swapfile 2>/dev/null && \
                   chmod 600 /swapfile && \
                   mkswap /swapfile >/dev/null 2>&1 && \
                   swapon /swapfile; then
                    log_ok "Swap file added and enabled"
                    local swap_mb
                    swap_mb=$(awk '/SwapTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
                    log_info "RAM: ${avail_ram_mb}MB + Swap: ${swap_mb}MB"
                    issues_found=$((issues_found - 1))
                else
                    log_error "Failed to create swap. Switching to single-node mode."
                    deploy_single_node
                    exit 0
                fi
                ;;
            3) log_warn "Continuing with insufficient RAM — OOM is likely" ;;
            *) echo "Aborted."; exit 1 ;;
        esac

    elif [[ "$avail_ram_mb" -lt 4096 ]]; then
        # --- Tier 3: 3-4GB — cluster mode OK ---
        log_ok "RAM meets minimum requirement (3GB+)"
        echo ""
        echo -e "  ${CYAN}How would you like to proceed?${NC}"
        echo -e "  ${GREEN}1)${NC} Cluster mode (recommended)"
        echo -e "  ${GREEN}2)${NC} Single-node mode instead"
        echo -e "  ${GREEN}3)${NC} Abort"
        echo ""
        choice=$(ask "Your choice" "1")
        case "$choice" in
            1) log_info "Continuing with cluster mode" ;;
            2) log_info "Switching to single-node mode..."; deploy_single_node; exit 0 ;;
            *) echo "Aborted."; exit 1 ;;
        esac

    else
        # --- Tier 4: ≥4GB — recommended for cluster ---
        log_ok "RAM meets recommended specs (4GB+)"
        echo ""
        echo -e "  ${CYAN}How would you like to proceed?${NC}"
        echo -e "  ${GREEN}1)${NC} Cluster mode (recommended)"
        echo -e "  ${GREEN}2)${NC} Single-node mode instead"
        echo -e "  ${GREEN}3)${NC} Abort"
        echo ""
        choice=$(ask "Your choice" "1")
        case "$choice" in
            1) log_info "Continuing with cluster mode" ;;
            2) log_info "Switching to single-node mode..."; deploy_single_node; exit 0 ;;
            *) echo "Aborted."; exit 1 ;;
        esac
    fi
}

deploy_single_node() {
    log_step "Setting up single-node OpenTenBase..."

    cleanup_old
    setup_repo
    install_package

    local port
    port=$(ask "Single-node port" "5432")

    log_step "Initializing single-node instance..."

    if command -v opentenbase-ctl >/dev/null 2>&1; then
        opentenbase-ctl init --mode=single --port="$port" || {
            log_error "Single-node initialization failed"
            exit 1
        }
    else
        log_error "opentenbase-ctl not found after installation"
        exit 1
    fi

    # Single-node mode starts GTM + Coordinator + Datanode (3 processes).
    # Try swap first; if container blocks swapon, tune memory params instead.
    ensure_swap_or_tune

    log_step "Starting single-node instance..."
    if command -v systemctl >/dev/null 2>&1 && systemctl start opentenbase 2>/dev/null; then
        log_ok "OpenTenBase started via systemd"
    else
        opentenbase-ctl start || {
            log_error "Failed to start OpenTenBase"
            exit 1
        }
    fi

    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${GREEN}  OpenTenBase Single-Node Ready!${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
    echo -e "  Connect:"
    echo -e "    ${GREEN}psql -h 127.0.0.1 -p ${port} -U opentenbase -d postgres${NC}"
    echo ""
    echo -e "  Manage:"
    echo -e "    opentenbase-ctl status"
    echo -e "    opentenbase-ctl stop"
    echo -e "    opentenbase-ctl start"
    echo ""
}

# ---------------------------------------------------------------------------
# Ensure enough memory for single-node mode (3 processes ~ 1.5GB)
# Strategy: try swap first; if container blocks swapon, tune PostgreSQL params
# ---------------------------------------------------------------------------
ensure_swap_or_tune() {
    local avail_ram_mb
    avail_ram_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")

    if [[ "$avail_ram_mb" -ge 3000 ]]; then
        return 0
    fi

    local swap_mb
    swap_mb=$(awk '/SwapTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")

    if [[ "$swap_mb" -ge 1024 ]]; then
        log_ok "Existing swap: ${swap_mb}MB — sufficient for single-node mode"
        return 0
    fi

    # --- Try adding swap (works on real VMs, fails in containers) ---
    log_info "Low RAM (${avail_ram_mb}MB) — trying to add 2G swap..."

    local swapfile="/swapfile"
    for sf in /swapfile /swapfile2; do
        if [[ -f "$sf" ]] && swapon --show | grep -q "$sf"; then
            swapfile="$sf"
            break
        fi
        if [[ ! -f "$sf" ]]; then
            swapfile="$sf"
            break
        fi
    done

    if fallocate -l 2G "$swapfile" 2>/dev/null && \
       chmod 600 "$swapfile" && \
       mkswap "$swapfile" >/dev/null 2>&1 && \
       swapon "$swapfile" 2>/dev/null; then
        if ! grep -q "$swapfile" /etc/fstab 2>/dev/null; then
            echo "$swapfile none swap sw 0 0" >> /etc/fstab
        fi
        swap_mb=$(awk '/SwapTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
        log_ok "Swap added: ${avail_ram_mb}MB RAM + ${swap_mb}MB swap"
        return 0
    fi

    # --- swapon failed (container environment) — tune memory params ---
    rm -f "$swapfile" 2>/dev/null
    log_warn "swapon not permitted (container environment) — tuning memory parameters instead"
    tune_low_memory
}

# ---------------------------------------------------------------------------
# Patch postgresql.conf with low-memory settings for container / 2GB servers
# Works in any environment — no special privileges needed beyond file write
# ---------------------------------------------------------------------------
tune_low_memory() {
    # Enable memory overcommit — PostgreSQL fork() needs this
    echo 1 > /proc/sys/vm/overcommit_memory 2>/dev/null || \
        log_warn "Cannot set overcommit_memory (container restriction)"

    local data_dir="${OT_DATA}/${DEFAULT_VERSION}"
    local conf_files=()
    for node in coord dn1; do
        local conf="${data_dir}/${node}/postgresql.conf"
        if [[ -f "$conf" ]]; then
            conf_files+=("$conf")
        fi
    done

    if [[ ${#conf_files[@]} -eq 0 ]]; then
        log_warn "No postgresql.conf found to tune — skipping"
        return 0
    fi

    log_info "Applying low-memory PostgreSQL settings..."

    for conf in "${conf_files[@]}"; do
        local node_name
        node_name=$(basename "$(dirname "$conf")")
        # Append overrides — PostgreSQL uses last value wins
        cat >> "$conf" <<EOF

# --- Low-memory overrides (auto-generated for ${avail_ram_mb:-low}MB RAM) ---
shared_buffers = 32MB
work_mem = 2MB
maintenance_work_mem = 64MB
effective_cache_size = 256MB
max_connections = 20
max_wal_senders = 5
max_pool_size = 10
wal_buffers = 4MB
bgwriter_delay = 200ms
bgwriter_lru_maxpages = 100
autovacuum_work_mem = 16MB
EOF
        log_ok "Tuned ${node_name}: shared_buffers=32MB, max_connections=20"
    done
}

# ---------------------------------------------------------------------------
# Step 2: Detect OS
# ---------------------------------------------------------------------------
detect_os() {
    log_step "Detecting operating system..."

    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS (no /etc/os-release)"
        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    ARCH=$(uname -m)
    PKG_MGR=""
    OS_FAMILY=""
    CODENAME=""

    case "$ID" in
        ubuntu)
            OS_FAMILY="deb"
            CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
            PKG_MGR="apt"
            ;;
        debian)
            OS_FAMILY="deb"
            CODENAME="$VERSION_CODENAME"
            PKG_MGR="apt"
            ;;
        linuxmint)
            OS_FAMILY="deb"
            case "$VERSION_ID" in
                21*) CODENAME="jammy" ;;
                22*) CODENAME="noble" ;;
                *)   CODENAME="jammy" ;;
            esac
            PKG_MGR="apt"
            ;;
        pop)
            OS_FAMILY="deb"
            case "$VERSION_ID" in
                22.04) CODENAME="jammy" ;;
                24.04) CODENAME="noble" ;;
                *)     CODENAME="jammy" ;;
            esac
            PKG_MGR="apt"
            ;;
        rocky|almalinux|centos|rhel|alinux|anolis)
            OS_FAMILY="rpm"
            PKG_MGR="dnf"
            ;;
        fedora)
            OS_FAMILY="rpm"
            PKG_MGR="dnf"
            ;;
        openeuler|hce)
            OS_FAMILY="rpm"
            PKG_MGR="dnf"
            ;;
        *)
            log_error "Unsupported distribution: $ID"
            echo "Supported: Ubuntu, Debian, Rocky, AlmaLinux, CentOS, Fedora, openEuler, Alibaba Cloud Linux, Anolis OS"
            exit 1
            ;;
    esac

    log_ok "Detected: ${ID} ${VERSION_ID} (${ARCH})"
    log_info "Package manager: ${PKG_MGR}, Family: ${OS_FAMILY}"
}

# ---------------------------------------------------------------------------
# Step 3: Cleanup old installation
# ---------------------------------------------------------------------------
cleanup_old() {
    log_step "Checking for previous installations..."

    local found_old=false

    # Check for running processes
    if pgrep -f "gtm" >/dev/null 2>&1 || pgrep -f "postgres.*-D" >/dev/null 2>&1; then
        found_old=true
        log_warn "Found running OpenTenBase processes"
        if ask_yes_no "Stop running processes?" "y"; then
            log_info "Stopping processes..."
            pkill -f "gtm -D" 2>/dev/null || true
            pkill -f "postgres.*-D" 2>/dev/null || true
            pkill -f "opentenbase_ctl" 2>/dev/null || true
            sleep 2
            # Force kill if still alive
            pkill -9 -f "gtm -D" 2>/dev/null || true
            pkill -9 -f "postgres.*-D" 2>/dev/null || true
            log_ok "Processes stopped"
        fi
    fi

    # Check for old data directories
    if [[ -d "${OT_DATA}" ]]; then
        found_old=true
        local data_size
        data_size=$(du -sh "${OT_DATA}" 2>/dev/null | cut -f1)
        log_warn "Found old data directory: ${OT_DATA} (${data_size})"
        if ask_yes_no "Remove old data directory? (this deletes all cluster data)" "y"; then
            rm -rf "${OT_DATA}"
            log_ok "Removed ${OT_DATA}"
        fi
    fi

    # Check for old logs
    if [[ -d "${OT_LOG}" ]]; then
        found_old=true
        log_warn "Found old log directory: ${OT_LOG}"
        if ask_yes_no "Remove old logs?" "y"; then
            rm -rf "${OT_LOG}"
            log_ok "Removed ${OT_LOG}"
        fi
    fi

    # Check for old binary installations (manual installs)
    for old_dir in "/data/opentenbase" "/usr/local/install/opentenbase"; do
        if [[ -d "$old_dir" ]]; then
            found_old=true
            local dir_size
            dir_size=$(du -sh "$old_dir" 2>/dev/null | cut -f1)
            log_warn "Found old binary directory: ${old_dir} (${dir_size})"
            if ask_yes_no "Remove ${old_dir}?" "y"; then
                rm -rf "$old_dir"
                log_ok "Removed ${old_dir}"
            fi
        fi
    done

    # Check for manually created swap files
    for swapfile in /swapfile2 /swapfile; do
        if [[ -f "$swapfile" ]] && swapon --show | grep -q "$swapfile"; then
            log_warn "Found manually created swap: ${swapfile}"
            if ask_yes_no "Disable and remove ${swapfile}?" "n"; then
                swapoff "$swapfile" 2>/dev/null || true
                rm -f "$swapfile"
                # Remove from fstab if present
                sed -i "\|${swapfile}|d" /etc/fstab 2>/dev/null || true
                log_ok "Removed ${swapfile}"
            fi
        fi
    done

    # Check for old packages
    if [[ "$PKG_MGR" == "dnf" ]]; then
        if rpm -q opentenbase >/dev/null 2>&1; then
            found_old=true
            log_warn "Found installed RPM package: opentenbase"
            if ask_yes_no "Remove old package?" "y"; then
                dnf remove -y opentenbase opentenbase-server opentenbase-client opentenbase-contrib opentenbase-dev opentenbase-doc 2>/dev/null || true
                log_ok "Old package removed"
            fi
        fi
    elif [[ "$PKG_MGR" == "apt" ]]; then
        if dpkg -l opentenbase >/dev/null 2>&1; then
            found_old=true
            log_warn "Found installed DEB package: opentenbase"
            if ask_yes_no "Remove old package?" "y"; then
                apt-get remove -y opentenbase opentenbase-server opentenbase-client opentenbase-contrib opentenbase-dev opentenbase-doc 2>/dev/null || true
                log_ok "Old package removed"
            fi
        fi
    fi

    # Clean old config
    if [[ -d "${OT_SYSCONF}" ]]; then
        found_old=true
        log_warn "Found old config directory: ${OT_SYSCONF}"
        if ask_yes_no "Remove old configuration?" "y"; then
            rm -rf "${OT_SYSCONF}"
            log_ok "Removed ${OT_SYSCONF}"
        fi
    fi

    if [[ "$found_old" == "false" ]]; then
        log_ok "No previous installation found"
    else
        log_ok "Cleanup complete"
    fi
}

# ---------------------------------------------------------------------------
# Step 4: Setup package repository
# ---------------------------------------------------------------------------
setup_repo() {
    log_step "Configuring OpenTenBase repository..."

    if [[ "$OS_FAMILY" == "deb" ]]; then
        setup_apt_repo
    else
        setup_rpm_repo
    fi
}

setup_apt_repo() {
    local cf_url="https://repo.blackevil217.com/apt"
    local github_url="https://cduestc-openatom-open-source-club.github.io/OpenTenBase-Packages/apt"
    local expected_fp="D8B2E316E1FF88EE178703549D8FA46F3A55D5F0"

    local repo_url=""
    for url in "$cf_url" "$github_url"; do
        if curl -sLf --connect-timeout 5 --max-time 10 "${url}/gpg-key.asc" -o /dev/null 2>/dev/null; then
            repo_url="$url"
            break
        fi
    done

    if [[ -z "$repo_url" ]]; then
        log_error "Cannot reach any APT repository mirror"
        exit 1
    fi

    log_info "Using mirror: ${repo_url}"

    # Map version to APT component
    local component="main"
    case "$DEFAULT_VERSION" in
        2.6.0|2.6) component="v2.6" ;;
        2.5.0|2.5) component="v2.5" ;;
    esac
    log_info "Version ${DEFAULT_VERSION} -> component: ${component}"

    # Add GPG key with fingerprint verification
    mkdir -p /usr/share/keyrings
    local tmpkey
    tmpkey=$(mktemp /tmp/otb-gpg-XXXXXX.asc)
    local imported=false
    for url in "${repo_url}/gpg-key.asc" "${github_url}/gpg-key.asc"; do
        if curl -sL --connect-timeout 10 --max-time 30 "$url" -o "$tmpkey" 2>/dev/null && \
           [ -s "$tmpkey" ] && head -1 "$tmpkey" | grep -q "BEGIN PGP"; then
            local got_fp
            got_fp=$(gpg --show-keys --with-colons "$tmpkey" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')
            if [[ "$got_fp" != "$expected_fp" ]]; then
                log_warn "GPG fingerprint mismatch from $url, skipping"
                continue
            fi
            gpg --batch --dearmor -o /usr/share/keyrings/opentenbase-archive-keyring.gpg < "$tmpkey" 2>/dev/null
            chmod 644 /usr/share/keyrings/opentenbase-archive-keyring.gpg
            imported=true
            break
        fi
    done
    rm -f "$tmpkey"

    if [[ "$imported" != "true" ]]; then
        log_error "GPG key import failed"
        exit 1
    fi
    log_ok "GPG key imported (fingerprint verified)"

    # Configure source
    cat > /etc/apt/sources.list.d/opentenbase.list <<EOF
# OpenTenBase APT Repository — v${DEFAULT_VERSION}
deb [signed-by=/usr/share/keyrings/opentenbase-archive-keyring.gpg] ${repo_url} ${CODENAME} ${component}
EOF
    chmod 644 /etc/apt/sources.list.d/opentenbase.list

    apt-get update -qq 2>/dev/null || log_warn "apt-get update failed"
    log_ok "APT repository configured (component: ${component})"
}

setup_rpm_repo() {
    local cf_url="https://repo.blackevil217.com/rpm"
    local github_url="https://cduestc-openatom-open-source-club.github.io/OpenTenBase-Packages/rpm"
    local expected_fp="D8B2E316E1FF88EE178703549D8FA46F3A55D5F0"

    local repo_url=""
    for url in "$cf_url" "$github_url"; do
        if curl -sLf --connect-timeout 5 --max-time 10 "${url}/gpg-key.asc" -o /dev/null 2>/dev/null; then
            repo_url="$url"
            break
        fi
    done

    if [[ -z "$repo_url" ]]; then
        log_error "Cannot reach any RPM repository mirror"
        exit 1
    fi

    log_info "Using mirror: ${repo_url}"

    # Import GPG key with fingerprint verification
    local tmpkey
    tmpkey=$(mktemp /tmp/otb-gpg-XXXXXX.asc)
    local imported=false
    for url in "${repo_url}/gpg-key.asc" "${github_url}/gpg-key.asc"; do
        if curl -sL --connect-timeout 10 --max-time 30 "$url" -o "$tmpkey" 2>/dev/null && \
           [ -s "$tmpkey" ] && head -1 "$tmpkey" | grep -q "BEGIN PGP"; then
            local got_fp
            got_fp=$(gpg --show-keys --with-colons "$tmpkey" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')
            if [[ "$got_fp" != "$expected_fp" ]]; then
                log_warn "GPG fingerprint mismatch from $url, skipping"
                continue
            fi
            rpm --import "$tmpkey" 2>/dev/null || true
            imported=true
            break
        fi
    done
    rm -f "$tmpkey"

    if [[ "$imported" != "true" ]]; then
        log_error "GPG key import failed"
        exit 1
    fi
    log_ok "GPG key imported (fingerprint verified)"

    # Detect repo subdir
    local repo_subdir
    case "$ID" in
        rocky|almalinux|centos|rhel|alinux|anolis)
            repo_subdir="el${VERSION_ID%%.*}"
            ;;
        fedora)
            repo_subdir="fedora"
            ;;
        openeuler|hce)
            repo_subdir="openeuler"
            ;;
    esac

    local full_url="${repo_url}/${repo_subdir}/${ARCH}"

    # Check if the repo URL is valid (repodata exists)
    if ! curl -sf --connect-timeout 5 --max-time 10 "${full_url}/repodata/repomd.xml" -o /dev/null 2>/dev/null; then
        if [ "$ARCH" = "aarch64" ]; then
            log_warn "aarch64 repo not available for $repo_subdir, falling back to x86_64"
            ARCH="x86_64"
            full_url="${repo_url}/${repo_subdir}/${ARCH}"
        else
            log_error "Repository not available: $full_url"
            exit 1
        fi
    fi

    cat > /etc/yum.repos.d/opentenbase.repo <<EOF
[opentenbase]
name=OpenTenBase Packages
baseurl=${full_url}
enabled=1
gpgcheck=1
gpgkey=${repo_url}/gpg-key.asc
EOF
    chmod 644 /etc/yum.repos.d/opentenbase.repo

    dnf makecache 2>/dev/null || log_warn "dnf makecache failed"
    log_ok "RPM repository configured"
}

# ---------------------------------------------------------------------------
# Step 5: Install package
# ---------------------------------------------------------------------------
install_package() {
    log_step "Installing OpenTenBase..."

    if [[ "$PKG_MGR" == "apt" ]]; then
        apt-get install -y opentenbase || {
            log_error "apt install failed"
            exit 1
        }
    else
        dnf install -y opentenbase || {
            log_error "dnf install failed"
            exit 1
        }
    fi

    log_ok "OpenTenBase installed"
}

# ---------------------------------------------------------------------------
# Step 6: Interactive configuration
# ---------------------------------------------------------------------------
interactive_config() {
    log_step "Configuring cluster..."

    local version="$DEFAULT_VERSION"
    local bin="${OT_BASE}/${version}/bin"

    # Check that the installed binaries work
    if [[ ! -x "${bin}/postgres" ]]; then
        log_error "Binaries not found at ${bin}/"
        log_error "Package installation may have failed"
        exit 1
    fi

    # Resolve service user
    local svc_user
    if id opentenbase >/dev/null 2>&1; then
        svc_user="opentenbase"
    elif id postgres >/dev/null 2>&1; then
        svc_user="postgres"
    else
        svc_user=$(ask "Service user" "opentenbase")
    fi

    # Interactive port configuration
    local gtm_port coord_port dn_port
    gtm_port=$(ask "GTM port" "$DEFAULT_GTM_PORT")
    coord_port=$(ask "Coordinator port (psql)" "$DEFAULT_COORD_PORT")
    dn_port=$(ask "Datanode port" "$DEFAULT_DN_PORT")

    # Data directory
    local data_dir
    data_dir=$(ask "Data directory" "${OT_DATA}/${version}")

    # Log directory
    local log_dir
    log_dir=$(ask "Log directory" "${OT_LOG}/${version}")

    # Write config
    local conf_dir="${OT_SYSCONF}/${version}"
    mkdir -p "${conf_dir}"

    cat > "${conf_dir}/opentenbase.conf" <<CONF
# OpenTenBase cluster configuration
# Generated by setup-cluster.sh on $(date -u '+%Y-%m-%d %H:%M:%S UTC')

ENABLED_NODES="gtm dn1 coord"

OTB_USER="${svc_user}"
OTB_GROUP="${svc_user}"
OTB_HOME="${OT_BASE}/${version}"

# Node names
COORD_NODENAME="coord"
DN1_NODENAME="dn1"

# Start/stop order
START_ORDER="gtm coord dn1"
STOP_ORDER="dn1 coord gtm"

# GTM
GTM_HOST=127.0.0.1
GTM_PGDATA="${data_dir}/gtm"
GTM_PORT=${gtm_port}
GTM_LOG="${log_dir}/gtm.log"

# Coordinator
COORD_HOST=127.0.0.1
COORD_PGDATA="${data_dir}/coord"
COORD_PORT=${coord_port}
COORD_POOLER_PORT=${DEFAULT_COORD_POOLER_PORT}
COORD_FORWARD_PORT=${DEFAULT_COORD_FORWARD_PORT}
COORD_LOG="${log_dir}/coord.log"

# Datanode
DN_HOST=127.0.0.1
DN1_PGDATA="${data_dir}/dn1"
DN1_PORT=${dn_port}
DN_PORT=${dn_port}
DN1_POOLER_PORT=${DEFAULT_DN_POOLER_PORT}
DN_POOLER_PORT=${DEFAULT_DN_POOLER_PORT}
DN1_FORWARD_PORT=${DEFAULT_DN_FORWARD_PORT}
DN_FORWARD_PORT=${DEFAULT_DN_FORWARD_PORT}
DN1_LOG="${log_dir}/dn1.log"
CONF

    # Create symlink for current version
    ln -sfn "${conf_dir}" "${OT_SYSCONF}/current"

    # Create data and log directories with correct ownership
    mkdir -p "${data_dir}" "${log_dir}"
    chown -R "${svc_user}:${svc_user}" "${data_dir}" "${log_dir}" 2>/dev/null || true

    # Copy pg_hba.conf template
    local tpl_dir="${conf_dir}"
    local src_dir
    # Find template source
    for d in "${conf_dir}" "/etc/opentenbase/${version}" "${OT_BASE}/${version}/share"; do
        if [[ -f "${d}/pg_hba.conf.template" ]]; then
            src_dir="$d"
            break
        fi
    done

    log_ok "Configuration written to ${conf_dir}/opentenbase.conf"
    log_info "  GTM:        port ${gtm_port}"
    log_info "  Coordinator: port ${coord_port}"
    log_info "  Datanode:   port ${dn_port}"
    log_info "  Data:       ${data_dir}"
    log_info "  Logs:       ${log_dir}"
    log_info "  User:       ${svc_user}"
}

# ---------------------------------------------------------------------------
# Step 7: Initialize and start cluster
# ---------------------------------------------------------------------------
init_and_start() {
    log_step "Initializing cluster..."

    if ! command -v opentenbase-ctl >/dev/null 2>&1; then
        log_error "opentenbase-ctl not found in PATH"
        log_info "Trying direct path: ${OT_BASE}/${DEFAULT_VERSION}/bin/opentenbase-ctl"
        if [[ -x "${OT_BASE}/${DEFAULT_VERSION}/bin/opentenbase-ctl" ]]; then
            export PATH="${OT_BASE}/${DEFAULT_VERSION}/bin:${PATH}"
        else
            log_error "opentenbase-ctl not available"
            exit 1
        fi
    fi

    opentenbase-ctl init || {
        log_error "Cluster initialization failed"
        exit 1
    }
    log_ok "Cluster initialized"

    log_step "Starting cluster..."
    opentenbase-ctl start || {
        log_error "Cluster start failed"
        # Show logs for debugging
        local conf_dir="${OT_SYSCONF}/current"
        # shellcheck disable=SC1090
        [[ -f "${conf_dir}/opentenbase.conf" ]] && . "${conf_dir}/opentenbase.conf"
        echo "--- GTM log (last 10) ---"
        tail -10 "${GTM_LOG:-/var/log/opentenbase/*/gtm.log}" 2>/dev/null || true
        echo "--- Coordinator log (last 10) ---"
        tail -10 "${COORD_LOG:-/var/log/opentenbase/*/coord.log}" 2>/dev/null || true
        echo "--- Datanode log (last 10) ---"
        tail -10 "${DN1_LOG:-/var/log/opentenbase/*/dn1.log}" 2>/dev/null || true
        exit 1
    }
    log_ok "Cluster started"
}

# ---------------------------------------------------------------------------
# Step 8: Verify deployment
# ---------------------------------------------------------------------------
verify_deployment() {
    log_step "Verifying deployment..."

    local conf_dir="${OT_SYSCONF}/current"
    if [[ ! -f "${conf_dir}/opentenbase.conf" ]]; then
        log_error "Config not found: ${conf_dir}/opentenbase.conf"
        return 1
    fi

    # shellcheck disable=SC1090
    . "${conf_dir}/opentenbase.conf"

    local psql="${OTB_HOME}/bin/psql -h 127.0.0.1 -p ${COORD_PORT} -U ${OTB_USER} -d postgres -X -q"
    local all_ok=true

    # Test 1: SQL connection
    if run_as_user "${OTB_USER}" "${psql} -c 'SELECT 1;'" >/dev/null 2>&1; then
        log_ok "SQL connection test passed"
    else
        log_error "SQL connection test failed"
        all_ok=false
    fi

    # Test 2: CREATE TABLE
    if run_as_user "${OTB_USER}" "${psql} -c 'CREATE TABLE _deploy_test (id int, name text);'" >/dev/null 2>&1; then
        log_ok "CREATE TABLE test passed"
        run_as_user "${OTB_USER}" "${psql} -c 'DROP TABLE _deploy_test;'" >/dev/null 2>&1 || true
    else
        log_error "CREATE TABLE test failed"
        all_ok=false
    fi

    # Test 3: Distributed table
    if run_as_user "${OTB_USER}" "${psql} -c 'CREATE TABLE _deploy_shard (id int) DISTRIBUTE BY SHARD(id);'" >/dev/null 2>&1; then
        log_ok "Distributed table test passed"
        run_as_user "${OTB_USER}" "${psql} -c 'DROP TABLE _deploy_shard;'" >/dev/null 2>&1 || true
    else
        log_warn "Distributed table test failed (non-critical)"
    fi

    if [[ "$all_ok" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

run_as_user() {
    local user="$1"
    shift
    if [[ "$user" == "$(whoami)" ]]; then
        "$@"
    else
        su -s /bin/bash -c "$*" "$user"
    fi
}

# ---------------------------------------------------------------------------
# Step 9: Show summary
# ---------------------------------------------------------------------------
show_summary() {
    local conf_dir="${OT_SYSCONF}/current"
    # shellcheck disable=SC1090
    [[ -f "${conf_dir}/opentenbase.conf" ]] && . "${conf_dir}/opentenbase.conf"

    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${GREEN}  OpenTenBase Deployment Complete!${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""
    echo "  Cluster status:"
    opentenbase-ctl status 2>/dev/null || true
    echo ""
    echo "  Connection:"
    echo "    psql -h 127.0.0.1 -p ${COORD_PORT:-5432} -U ${OTB_USER:-opentenbase} -d postgres"
    echo ""
    echo "  Management commands:"
    echo "    opentenbase-ctl status    # Check cluster status"
    echo "    opentenbase-ctl stop      # Stop cluster"
    echo "    opentenbase-ctl start     # Start cluster"
    echo "    opentenbase-ctl restart   # Restart cluster"
    echo ""
    echo "  Quick test:"
    echo "    psql -h 127.0.0.1 -p ${COORD_PORT:-5432} -U ${OTB_USER:-opentenbase} -d postgres -c \\"
    echo "      'CREATE TABLE test (id int) DISTRIBUTE BY SHARD(id);'"
    echo ""
    echo -e "${BOLD}========================================${NC}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo ""
    echo -e "${BOLD}========================================${NC}"
    echo -e "${BOLD}  OpenTenBase One-Click Deployment${NC}"
    echo -e "${BOLD}========================================${NC}"
    echo ""

    check_root
    detect_os
    preflight_check
    cleanup_old
    setup_repo
    install_package
    interactive_config
    init_and_start

    if verify_deployment; then
        show_summary
    else
        log_error "Deployment verification failed"
        echo "Check logs: ${OT_LOG}/"
        exit 1
    fi
}

main "$@"
