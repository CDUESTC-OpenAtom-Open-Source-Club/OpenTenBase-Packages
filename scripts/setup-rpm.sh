#!/bin/bash
# OpenTenBase RPM Repository Setup Script
# Usage: curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-rpm.sh | sudo bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# Auto-detect fastest mirror (Cloudflare CDN first, then Gitee for China, GitHub fallback)
detect_mirror() {
    local cf_url="https://apt.blackevil217.com/rpm"
    local gitee_url="https://blackEvil217.gitee.io/opentenbase-packages/rpm"
    local github_url="https://muzimu217.github.io/OpenTenBase-deb/rpm"

    # Try Cloudflare CDN first (global acceleration)
    if curl -sLf --connect-timeout 5 --max-time 10 "${cf_url}/gpg-key.asc" -o /dev/null 2>/dev/null; then
        REPO_BASE_URL="$cf_url"
        log_info "Using Cloudflare CDN mirror (apt.blackevil217.com)"
    # Try Gitee second (faster in China)
    elif curl -sLf --connect-timeout 5 --max-time 10 "${gitee_url}/gpg-key.asc" -o /dev/null 2>/dev/null; then
        REPO_BASE_URL="$gitee_url"
        log_info "Using Gitee mirror (faster in China)"
    else
        REPO_BASE_URL="$github_url"
        log_info "Using GitHub repository"
    fi
}

detect_mirror
GPG_KEY_URL="${REPO_BASE_URL}/gpg-key.asc"
# Pinned signing-key fingerprint. The downloaded key is verified against this
# value (when gpg is available) so a compromised mirror cannot substitute a
# different key.
EXPECTED_FINGERPRINT="D8B2E316E1FF88EE178703549D8FA46F3A55D5F0"

# Verify an (armored) GPG key file against the pinned fingerprint.
# Returns 0 if it matches, 1 on mismatch, 2 if gpg is unavailable (skip).
verify_key_fingerprint() {
    local keyfile="$1"
    command -v gpg >/dev/null 2>&1 || return 2
    local got
    got=$(gpg --show-keys --with-colons "$keyfile" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')
    [ "$got" = "$EXPECTED_FINGERPRINT" ] && return 0
    log_error "GPG key fingerprint mismatch — rejecting key!"
    log_error "  expected: $EXPECTED_FINGERPRINT"
    log_error "  got:      ${got:-<none>}"
    return 1
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script requires root privileges"
        echo "Please use: sudo bash $0"
        exit 1
    fi
}

detect_os() {
    log_step "Detecting operating system ..."

    if [ ! -f /etc/os-release ]; then
        log_error "Cannot detect operating system"
        exit 1
    fi

    . /etc/os-release

    case "$ID" in
        rocky|almalinux|centos|rhel)
            case "$VERSION_ID" in
                8*|9*)
                    REPO_SUBDIR="el${VERSION_ID%%.*}"
                    ;;
                *)
                    log_warn "$ID $VERSION_ID not tested, using el9 repo"
                    REPO_SUBDIR="el9"
                    ;;
            esac
            ;;
        fedora)
            REPO_SUBDIR="fedora"
            ;;
        openeuler|hce)
            REPO_SUBDIR="openeuler"
            ;;
        *)
            log_error "Unsupported distribution: $ID"
            echo "Supported: Rocky Linux 8/9, AlmaLinux 8/9, CentOS Stream 8/9, Fedora 40+, openEuler 22.03+, Huawei Cloud EulerOS"
            exit 1
            ;;
    esac

    ARCH=$(uname -m)
    log_info "Detected: $ID $VERSION_ID ($ARCH)"
}

add_gpg_key() {
    log_step "Adding GPG key ..."

    # Try multiple mirrors with robust fallback
    local imported=false
    local tmpkey
    tmpkey=$(mktemp /tmp/opentenbase-gpg-key-XXXXXX.asc)
    for url in "$GPG_KEY_URL" "https://muzimu217.github.io/OpenTenBase-deb/rpm/gpg-key.asc"; do
        # Always download first so the key can be verified against the pinned
        # fingerprint before it is imported into the rpm trust store.
        if curl -sL --connect-timeout 10 --max-time 30 "$url" -o "$tmpkey" 2>/dev/null && \
           [ -s "$tmpkey" ] && head -1 "$tmpkey" | grep -q "BEGIN PGP"; then
            verify_key_fingerprint "$tmpkey"; rc=$?
            if [ "$rc" -eq 1 ]; then
                # Mismatch: skip this source entirely.
                rm -f "$tmpkey"
                continue
            elif [ "$rc" -eq 2 ]; then
                log_warn "gpg 不可用，跳过指纹校验（仍依赖 rpm gpgcheck）"
            fi
            rpm --import "$tmpkey" 2>/dev/null && imported=true && rm -f "$tmpkey" && break
        fi
        rm -f "$tmpkey"
    done

    if [ "$imported" = "true" ]; then
        log_info "GPG key imported"
    else
        log_error "GPG key import failed"
        exit 1
    fi
}

configure_repo() {
    log_step "Configuring YUM/DNF repository ..."

    local repo_url="${REPO_BASE_URL}/${REPO_SUBDIR}/${ARCH}"

    cat > /etc/yum.repos.d/opentenbase.repo << EOF
[opentenbase]
name=OpenTenBase Packages
baseurl=${repo_url}
enabled=1
gpgcheck=1
gpgkey=${GPG_KEY_URL}
EOF

    chmod 644 /etc/yum.repos.d/opentenbase.repo
    log_info "Repository configured: /etc/yum.repos.d/opentenbase.repo"
}

update_cache() {
    log_step "Updating package cache ..."

    if command -v dnf &>/dev/null; then
        dnf makecache 2>/dev/null || log_warn "dnf makecache failed"
    else
        yum makecache 2>/dev/null || log_warn "yum makecache failed"
    fi

    log_info "Package cache updated"
}

show_install_info() {
    echo ""
    echo "========================================"
    echo -e "${GREEN}  OpenTenBase repository configured!${NC}"
    echo "========================================"
    echo ""
    echo "Install OpenTenBase:"
    echo ""
    echo "  # Full package (recommended)"
    if command -v dnf &>/dev/null; then
        echo "  sudo dnf install opentenbase"
    else
        echo "  sudo yum install opentenbase"
    fi
    echo ""
    echo "  # Or install individual components"
    echo "  # opentenbase-server"
    echo "  # opentenbase-client"
    echo "  # opentenbase-contrib"
    echo ""
    echo "Quick start:"
    echo "  opentenbase-ctl init    # Initialize cluster"
    echo "  opentenbase-ctl start   # Start all nodes"
    echo "  opentenbase-ctl status  # Check status"
    echo ""
    echo "========================================"
}

main() {
    echo "========================================"
    echo "  OpenTenBase RPM Repository Setup"
    echo "========================================"
    echo ""

    check_root
    detect_os
    add_gpg_key
    configure_repo
    update_cache
    show_install_info
}

main "$@"
