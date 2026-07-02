#!/bin/bash
# OpenTenBase RPM Repository Setup Script
# Usage: curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh | sudo bash

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

# Auto-detect fastest mirror (Cloudflare CDN first, GitHub fallback)
detect_mirror() {
    local cf_url="https://repo.blackevil217.com/rpm"
    local github_url="https://cduestc-openatom-open-source-club.github.io/OpenTenBase-Packages/rpm"

    # Try Cloudflare CDN first (global acceleration)
    if curl -sLf --connect-timeout 5 --max-time 10 "${cf_url}/gpg-key.asc" -o /dev/null 2>/dev/null; then
        REPO_BASE_URL="$cf_url"
        log_info "Using Cloudflare CDN mirror (repo.blackevil217.com/rpm)"
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
        rocky|almalinux|centos|rhel|opencloudos|anolis|tencentos)
            # RHEL-compatible distros. The last three (OpenCloudOS, Anolis OS,
            # TencentOS) are RHEL 8/9 compatible but their ID was missing from
            # the original whitelist, causing a hard exit on otherwise working
            # systems. They use the same el8/el9 repo subdirectory.
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
            # Fallback for unknown IDs whose /etc/os-release exposes an
            # ID_LIKE indicating RHEL/fedora lineage (e.g. future distros).
            # This avoids a hard exit on RHEL-compatible systems we have not
            # explicitly listed above.
            if echo "$ID_LIKE" | grep -qiE "rhel|fedora|centos"; then
                case "$VERSION_ID" in
                    8*) REPO_SUBDIR="el8" ;;
                    9*) REPO_SUBDIR="el9" ;;
                    *)  log_warn "$ID $VERSION_ID untested (ID_LIKE=$ID_LIKE), using el9 repo"; REPO_SUBDIR="el9" ;;
                esac
                log_warn "$ID is not in the tested list but ID_LIKE=$ID_LIKE; using $REPO_SUBDIR repo (untested)"
            else
                log_error "Unsupported distribution: $ID"
                echo "Supported: Rocky Linux 8/9, AlmaLinux 8/9, CentOS Stream 8/9, Fedora 40+, openEuler 22.03+, Huawei Cloud EulerOS, OpenCloudOS 8/9, Anolis OS 8/9"
                exit 1
            fi
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
    for url in "$GPG_KEY_URL" "https://cduestc-openatom-open-source-club.github.io/OpenTenBase-Packages/rpm/gpg-key.asc"; do
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

    # Check if the repo URL is valid (repodata exists)
    if ! curl -sf --connect-timeout 5 --max-time 10 "${repo_url}/repodata/repomd.xml" -o /dev/null 2>/dev/null; then
        if [ "$ARCH" = "aarch64" ]; then
            log_warn "aarch64 repo not available for $REPO_SUBDIR, falling back to x86_64"
            ARCH="x86_64"
            repo_url="${REPO_BASE_URL}/${REPO_SUBDIR}/${ARCH}"
        else
            log_error "Repository not available: $repo_url"
            exit 1
        fi
    fi

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

# Install libpqxx dependency if needed (EPEL has older 7.6.x/7.7.x which breaks opentenbase_ctl)
install_libpqxx_dependency() {
    log_step "Checking libpqxx dependency..."

    # Check if system has libpqxx 7.9
    local system_libpqxx=$(rpm -q libpqxx-devel --queryformat '%{VERSION}' 2>/dev/null || echo "")

    if [ -n "$system_libpqxx" ]; then
        local major_version=$(echo "$system_libpqxx" | cut -d. -f1)
        local minor_version=$(echo "$system_libpqxx" | cut -d. -f2)

        if [ "$major_version" = "7" ] && [ "$minor_version" -ge "9" ]; then
            log_info "System libpqxx version is sufficient: $system_libpqxx"
            return 0
        else
            log_warn "System libpqxx version is too old: $system_libpqxx (need >= 7.9)"
        fi
    else
        log_info "System does not have libpqxx-devel package"
    fi

    # Download and install libpqxx 7.9.2 from our CDN/GitHub Release
    log_info "Downloading libpqxx 7.9.2..."

    local libpqxx_url="https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/libpqxx-7.9.2"

    # Determine package name based on distro
    local distro_tag=""
    case "$ID" in
        rocky|almalinux|centos|rhel|opencloudos|anolis|tencentos)
            distro_tag="el${VERSION_ID%%.*}"
            ;;
        fedora)
            distro_tag="fc${VERSION_ID}"
            ;;
        openeuler|hce)
            distro_tag="oe${VERSION_ID%%.*}"
            ;;
    esac

    local libpqxx_pkg="libpqxx-7.9.2-1.opentenbase.${distro_tag}.${ARCH}.rpm"
    local libpqxx_dev_pkg="libpqxx-devel-7.9.2-1.opentenbase.${distro_tag}.${ARCH}.rpm"

    # Try to download from CDN first, then GitHub Release
    local tmpdir=$(mktemp -d)
    local success=false

    for base_url in "$libpqxx_url" "https://repo.blackevil217.com/deps"; do
        # Download packages
        if curl -sL --connect-timeout 10 --max-time 60 "${base_url}/${libpqxx_pkg}" -o "$tmpdir/${libpqxx_pkg}" 2>/dev/null && \
           [ -s "$tmpdir/${libpqxx_pkg}" ]; then
            if curl -sL --connect-timeout 10 --max-time 60 "${base_url}/${libpqxx_dev_pkg}" -o "$tmpdir/${libpqxx_dev_pkg}" 2>/dev/null && \
               [ -s "$tmpdir/${libpqxx_dev_pkg}" ]; then
                success=true
                break
            fi
        fi
    done

    if [ "$success" = "true" ]; then
        log_info "Installing libpqxx 7.9.2..."
        # Remove old libpqxx if exists
        rpm -e libpqxx-devel libpqxx 2>/dev/null || true

        # Install new packages
        if command -v dnf &>/dev/null; then
            dnf install -y "$tmpdir/${libpqxx_pkg}" "$tmpdir/${libpqxx_dev_pkg}" || {
                # Fix missing libpq dependency if needed
                dnf install -y libpq-devel
                dnf install -y "$tmpdir/${libpqxx_pkg}" "$tmpdir/${libpqxx_dev_pkg}"
            }
        else
            yum install -y "$tmpdir/${libpqxx_pkg}" "$tmpdir/${libpqxx_dev_pkg}" || {
                yum install -y libpq-devel
                yum install -y "$tmpdir/${libpqxx_pkg}" "$tmpdir/${libpqxx_dev_pkg}"
            }
        fi

        log_info "libpqxx 7.9.2 installed"
        rm -rf "$tmpdir"
        return 0
    else
        log_warn "Cannot download libpqxx from CDN, will build from source during installation"
        log_info "opentenbase_ctl may require additional build time"
        rm -rf "$tmpdir"
        return 0
    fi
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
    echo "  # 1. Install sshpass + edit INI config"
    echo "  #    Template: /etc/opentenbase/5.0/opentenbase_config.ini.example"
    echo "  opentenbase_ctl install -c /tmp/otb_config.ini   # Install cluster"
    echo "  opentenbase_ctl start      # Start cluster"
    echo "  opentenbase_ctl status     # Check status"
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
    install_libpqxx_dependency
    show_install_info
}

main "$@"
