#!/bin/bash
# OpenTenBase Installation Test Script
# Usage: sudo bash test-install.sh
#
# Tests .deb package installation on real servers
# Supports: Ubuntu 20.04/22.04/24.04, Debian 11/12

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Config
TAG="v5.0-multi9"
REPO_URL="https://github.com/muzimu217/opentenbase-deb/releases/download/${TAG}"
LOG_FILE="/tmp/opentenbase-test-$(date +%Y%m%d-%H%M%S).log"

# Logging
log_info()  { echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1" | tee -a "$LOG_FILE"; }
log_pass()  { echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$LOG_FILE"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $1" | tee -a "$LOG_FILE"; }

# Check root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script requires root privileges"
        echo "Please run: sudo bash $0"
        exit 1
    fi
}

# Detect OS
detect_os() {
    log_step "Detecting OS..."

    if [ ! -f /etc/os-release ]; then
        log_error "Cannot detect OS version"
        exit 1
    fi

    . /etc/os-release

    OS_ID="$ID"
    OS_VERSION="$VERSION_ID"

    case "$ID" in
        ubuntu)
            case "$VERSION_ID" in
                20.04) CODENAME="focal" ;;
                22.04) CODENAME="jammy" ;;
                24.04) CODENAME="noble" ;;
                *)     log_error "Unsupported Ubuntu version: $VERSION_ID"; exit 1 ;;
            esac
            ;;
        debian)
            case "$VERSION_ID" in
                11) CODENAME="bullseye" ;;
                12) CODENAME="bookworm" ;;
                *)  log_error "Unsupported Debian version: $VERSION_ID"; exit 1 ;;
            esac
            ;;
        *)
            log_error "Unsupported OS: $ID"
            exit 1
            ;;
    esac

    log_info "Detected: $OS_ID $OS_VERSION ($CODENAME)"
}

# Cleanup old installation
cleanup_old() {
    log_step "Cleaning up old installation..."

    if command -v opentenbase-ctl &> /dev/null; then
        opentenbase-ctl stop 2>/dev/null || true
    fi

    apt-get remove -y opentenbase opentenbase-server opentenbase-client opentenbase-contrib libopentenbase-dev opentenbase-doc 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true

    rm -rf /var/lib/opentenbase 2>/dev/null || true
    rm -rf /var/log/opentenbase 2>/dev/null || true
    rm -rf /var/run/opentenbase 2>/dev/null || true
    rm -rf /etc/opentenbase 2>/dev/null || true

    log_info "Cleanup done"
}

# Download packages
download_packages() {
    log_step "Downloading OpenTenBase packages..."

    local pkg_dir="/tmp/opentenbase-debs"
    mkdir -p "$pkg_dir"
    cd "$pkg_dir"
    rm -f *.deb

    local packages=(
        "opentenbase_5.0-1ubuntu1.${CODENAME}_all.deb"
        "opentenbase-server_5.0-1ubuntu1.${CODENAME}_amd64.deb"
        "opentenbase-client_5.0-1ubuntu1.${CODENAME}_amd64.deb"
        "opentenbase-contrib_5.0-1ubuntu1.${CODENAME}_amd64.deb"
        "libopentenbase-dev_5.0-1ubuntu1.${CODENAME}_amd64.deb"
    )

    for pkg in "${packages[@]}"; do
        log_info "Downloading: $pkg"
        if ! curl -sLO "${REPO_URL}/${pkg}"; then
            log_error "Download failed: $pkg"
            return 1
        fi
    done

    local count=$(ls -1 *.deb 2>/dev/null | wc -l)
    if [ "$count" -lt 4 ]; then
        log_error "Incomplete download: only $count packages"
        return 1
    fi

    log_info "Downloaded: $count packages"
    ls -la *.deb | tee -a "$LOG_FILE"
}

# Install packages
install_packages() {
    log_step "Installing OpenTenBase packages..."

    cd /tmp/opentenbase-debs

    # Install dependencies
    apt-get update -qq
    apt-get install -y -qq libreadline7 libssl1.1 libxml2 libcurl4 2>/dev/null || \
    apt-get install -y -qq libreadline8 libssl3 libxml2 libcurl4 2>/dev/null || true

    # Install main packages
    if ! apt-get install -y ./*.deb 2>&1 | tee -a "$LOG_FILE"; then
        log_warn "apt-get install failed, trying dpkg..."
        dpkg -i ./*.deb 2>&1 | tee -a "$LOG_FILE" || true
        apt-get install -f -y 2>&1 | tee -a "$LOG_FILE"
    fi

    # Verify installation
    if command -v opentenbase-ctl &> /dev/null; then
        log_pass "opentenbase-ctl installed"
    else
        log_fail "opentenbase-ctl not found"
        return 1
    fi

    if command -v postgres &> /dev/null || [ -f /usr/lib/opentenbase/bin/postgres ]; then
        log_pass "postgres installed"
    else
        log_fail "postgres not found"
        return 1
    fi
}

# Test init
test_init() {
    log_step "Testing cluster init..."

    if opentenbase-ctl init 2>&1 | tee -a "$LOG_FILE"; then
        log_pass "Cluster init succeeded"
    else
        log_fail "Cluster init failed"
        return 1
    fi
}

# Test start
test_start() {
    log_step "Testing cluster start..."

    if opentenbase-ctl start 2>&1 | tee -a "$LOG_FILE"; then
        log_pass "Cluster start succeeded"
    else
        log_fail "Cluster start failed"
        return 1
    fi

    sleep 5
    opentenbase-ctl status 2>&1 | tee -a "$LOG_FILE"
}

# Test connection
test_connection() {
    log_step "Testing database connection..."

    sleep 3

    if /usr/lib/opentenbase/bin/psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres -c "SELECT version();" 2>&1 | tee -a "$LOG_FILE"; then
        log_pass "Database connection succeeded"
    else
        log_warn "Database connection failed (may need pg_hba.conf config)"
    fi
}

# Test stop
test_stop() {
    log_step "Testing cluster stop..."

    if opentenbase-ctl stop 2>&1 | tee -a "$LOG_FILE"; then
        log_pass "Cluster stop succeeded"
    else
        log_fail "Cluster stop failed"
    fi
}

# Show results
show_results() {
    echo ""
    echo "========================================"
    echo "  OpenTenBase Installation Test Results"
    echo "========================================"
    echo ""
    echo "System: $OS_ID $OS_VERSION ($CODENAME)"
    echo "Time:   $(date)"
    echo "Log:    $LOG_FILE"
    echo ""

    local pass_count=$(grep -c "\[PASS\]" "$LOG_FILE" 2>/dev/null || echo "0")
    local fail_count=$(grep -c "\[FAIL\]" "$LOG_FILE" 2>/dev/null || echo "0")

    echo "Results:"
    echo -e "  Passed: ${GREEN}$pass_count${NC}"
    echo -e "  Failed: ${RED}$fail_count${NC}"
    echo ""

    if [ "$fail_count" -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
    else
        echo -e "${RED}Some tests failed. Check log for details.${NC}"
    fi
    echo "========================================"
}

# Main
main() {
    echo "========================================"
    echo "  OpenTenBase Installation Test"
    echo "========================================"
    echo ""
    echo "TAG:  $TAG"
    echo "Log:  $LOG_FILE"
    echo ""

    check_root
    detect_os
    cleanup_old
    download_packages
    install_packages
    test_init
    test_start
    test_connection
    test_stop
    show_results
}

main "$@"
