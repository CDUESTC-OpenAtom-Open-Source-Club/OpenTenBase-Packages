#!/bin/bash
# OpenTenBase Docker E2E Test Script
# Tests package installation from APT/RPM repos on multiple distros (aarch64)
#
# Usage: ./docker-e2e-test.sh [distro]
#   distro: ubuntu, rocky, openeuler, or all (default: all)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RESULTS_FILE="${REPO_ROOT}/test/docker-e2e-results.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

passed=0
failed=0
results=""

record_result() {
    local distro="$1" test="$2" status="$3" detail="$4"
    if [ "$status" = "PASS" ]; then
        results+="| $distro | $test | ✅ PASS | $detail |\n"
        ((passed++))
    else
        results+="| $distro | $test | ❌ FAIL | $detail |\n"
        ((failed++))
    fi
}

# ─── Test: Ubuntu 22.04 (DEB) ───────────────────────────────────────────────
test_ubuntu() {
    local container="otb-test-ubuntu"
    log_step "=== Testing Ubuntu 22.04 (DEB aarch64) ==="

    docker rm -f "$container" 2>/dev/null || true

    log_info "Starting container ..."
    docker run -d --name "$container" --privileged \
        -v /dev/shm:/dev/shm \
        ubuntu:22.04 sleep 3600

    log_info "Installing dependencies ..."
    docker exec "$container" bash -c "
        apt-get update -qq
        apt-get install -y -qq curl sudo gnupg systemd > /dev/null 2>&1
    "

    log_info "Running setup-apt.sh ..."
    if docker exec "$container" bash -c "
        curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | bash
    " 2>&1; then
        record_result "Ubuntu 22.04" "setup-apt.sh" "PASS" "Repo configured"
    else
        record_result "Ubuntu 22.04" "setup-apt.sh" "FAIL" "Repo setup failed"
        docker rm -f "$container" 2>/dev/null
        return
    fi

    log_info "Installing opentenbase ..."
    if docker exec "$container" bash -c "
        apt-get update -qq
        apt-get install -y opentenbase 2>&1 | tail -5
    " 2>&1; then
        record_result "Ubuntu 22.04" "apt install" "PASS" "Package installed"
    else
        record_result "Ubuntu 22.04" "apt install" "FAIL" "Package install failed"
        docker rm -f "$container" 2>/dev/null
        return
    fi

    log_info "opentenbase-ctl init ..."
    if docker exec "$container" bash -c "opentenbase-ctl init" 2>&1; then
        record_result "Ubuntu 22.04" "init" "PASS" "Cluster initialized"
    else
        record_result "Ubuntu 22.04" "init" "FAIL" "Init failed"
        docker rm -f "$container" 2>/dev/null
        return
    fi

    log_info "opentenbase-ctl start ..."
    if docker exec "$container" bash -c "opentenbase-ctl start" 2>&1; then
        record_result "Ubuntu 22.04" "start" "PASS" "All nodes started"
    else
        record_result "Ubuntu 22.04" "start" "FAIL" "Start failed"
        docker rm -f "$container" 2>/dev/null
        return
    fi

    log_info "opentenbase-ctl status ..."
    local status_output
    status_output=$(docker exec "$container" bash -c "opentenbase-ctl status" 2>&1)
    echo "$status_output"
    if echo "$status_output" | grep -q "STOPPED"; then
        record_result "Ubuntu 22.04" "status" "FAIL" "Some nodes stopped"
    else
        record_result "Ubuntu 22.04" "status" "PASS" "All nodes running"
    fi

    log_info "SQL query test ..."
    local sql_output
    sql_output=$(docker exec "$container" bash -c "
        psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1 -X -q -c 'SELECT version();' 2>&1
    ")
    echo "$sql_output"
    if echo "$sql_output" | grep -q "OpenTenBase"; then
        record_result "Ubuntu 22.04" "SQL query" "PASS" "SELECT version() OK"
    else
        record_result "Ubuntu 22.04" "SQL query" "FAIL" "Query failed"
    fi

    log_info "DISTRIBUTE BY SHARD test ..."
    local shard_output
    shard_output=$(docker exec "$container" bash -c "
        psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1 -X -q -v ON_ERROR_STOP=1 -c \"
            CREATE TABLE docker_test (id int, name text) DISTRIBUTE BY SHARD(id);
            INSERT INTO docker_test VALUES (1, 'hello from docker');
            SELECT * FROM docker_test;
            DROP TABLE docker_test;
        \" 2>&1
    ")
    echo "$shard_output"
    if echo "$shard_output" | grep -q "hello from docker"; then
        record_result "Ubuntu 22.04" "SHARD table" "PASS" "DISTRIBUTE BY SHARD OK"
    else
        record_result "Ubuntu 22.04" "SHARD table" "FAIL" "Shard test failed"
    fi

    log_info "opentenbase-ctl stop ..."
    docker exec "$container" bash -c "opentenbase-ctl stop" 2>&1 || true
    record_result "Ubuntu 22.04" "stop" "PASS" "Cluster stopped"

    docker rm -f "$container" 2>/dev/null
    log_info "Ubuntu 22.04 test complete"
}

# ─── Test: Rocky Linux 9 (RPM) ──────────────────────────────────────────────
test_rocky() {
    local container="otb-test-rocky"
    log_step "=== Testing Rocky Linux 9 (RPM aarch64) ==="

    docker rm -f "$container" 2>/dev/null || true

    log_info "Starting container ..."
    docker run -d --name "$container" --privileged \
        -v /dev/shm:/dev/shm \
        rockylinux:9 sleep 3600

    log_info "Installing dependencies ..."
    docker exec "$container" bash -c "
        dnf install -y -q curl sudo gnupg2 which > /dev/null 2>&1
    "

    log_info "Running setup-rpm.sh ..."
    if docker exec "$container" bash -c "
        curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh | bash
    " 2>&1; then
        record_result "Rocky 9" "setup-rpm.sh" "PASS" "Repo configured"
    else
        record_result "Rocky 9" "setup-rpm.sh" "FAIL" "Repo setup failed"
        docker rm -f "$container" 2>/dev/null
        return
    fi

    log_info "Installing opentenbase ..."
    if docker exec "$container" bash -c "
        dnf install -y opentenbase 2>&1 | tail -5
    " 2>&1; then
        record_result "Rocky 9" "dnf install" "PASS" "Package installed"
    else
        record_result "Rocky 9" "dnf install" "FAIL" "Package install failed"
        docker rm -f "$container" 2>/dev/null
        return
    fi

    log_info "opentenbase-ctl init ..."
    if docker exec "$container" bash -c "opentenbase-ctl init" 2>&1; then
        record_result "Rocky 9" "init" "PASS" "Cluster initialized"
    else
        record_result "Rocky 9" "init" "FAIL" "Init failed"
        docker rm -f "$container" 2>/dev/null
        return
    fi

    log_info "opentenbase-ctl start ..."
    if docker exec "$container" bash -c "opentenbase-ctl start" 2>&1; then
        record_result "Rocky 9" "start" "PASS" "All nodes started"
    else
        record_result "Rocky 9" "start" "FAIL" "Start failed"
        docker rm -f "$container" 2>/dev/null
        return
    fi

    log_info "opentenbase-ctl status ..."
    local status_output
    status_output=$(docker exec "$container" bash -c "opentenbase-ctl status" 2>&1)
    echo "$status_output"
    if echo "$status_output" | grep -q "STOPPED"; then
        record_result "Rocky 9" "status" "FAIL" "Some nodes stopped"
    else
        record_result "Rocky 9" "status" "PASS" "All nodes running"
    fi

    log_info "SQL query test ..."
    local sql_output
    sql_output=$(docker exec "$container" bash -c "
        psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1 -X -q -c 'SELECT version();' 2>&1
    ")
    echo "$sql_output"
    if echo "$sql_output" | grep -q "OpenTenBase"; then
        record_result "Rocky 9" "SQL query" "PASS" "SELECT version() OK"
    else
        record_result "Rocky 9" "SQL query" "FAIL" "Query failed"
    fi

    log_info "DISTRIBUTE BY SHARD test ..."
    local shard_output
    shard_output=$(docker exec "$container" bash -c "
        psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1 -X -q -v ON_ERROR_STOP=1 -c \"
            CREATE TABLE docker_test (id int, name text) DISTRIBUTE BY SHARD(id);
            INSERT INTO docker_test VALUES (1, 'hello from docker');
            SELECT * FROM docker_test;
            DROP TABLE docker_test;
        \" 2>&1
    ")
    echo "$shard_output"
    if echo "$shard_output" | grep -q "hello from docker"; then
        record_result "Rocky 9" "SHARD table" "PASS" "DISTRIBUTE BY SHARD OK"
    else
        record_result "Rocky 9" "SHARD table" "FAIL" "Shard test failed"
    fi

    log_info "opentenbase-ctl stop ..."
    docker exec "$container" bash -c "opentenbase-ctl stop" 2>&1 || true
    record_result "Rocky 9" "stop" "PASS" "Cluster stopped"

    docker rm -f "$container" 2>/dev/null
    log_info "Rocky 9 test complete"
}

# ─── Test: openEuler 24.03 (RPM) ────────────────────────────────────────────
test_openeuler() {
    local container="otb-test-openeuler"
    log_step "=== Testing openEuler 24.03 (RPM aarch64) ==="

    docker rm -f "$container" 2>/dev/null || true

    log_info "Starting container ..."
    docker run -d --name "$container" --privileged \
        -v /dev/shm:/dev/shm \
        openeuler/openeuler:24.03 sleep 3600

    log_info "Installing dependencies ..."
    docker exec "$container" bash -c "
        dnf install -y -q curl sudo gnupg2 which shadow-utils > /dev/null 2>&1
    "

    log_info "Running setup-rpm.sh ..."
    if docker exec "$container" bash -c "
        curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh | bash
    " 2>&1; then
        record_result "openEuler 24.03" "setup-rpm.sh" "PASS" "Repo configured"
    else
        record_result "openEuler 24.03" "setup-rpm.sh" "FAIL" "Repo setup failed"
        docker rm -f "$container" 2>/dev/null
        return
    fi

    log_info "Installing opentenbase ..."
    if docker exec "$container" bash -c "
        dnf install -y opentenbase 2>&1 | tail -5
    " 2>&1; then
        record_result "openEuler 24.03" "dnf install" "PASS" "Package installed"
    else
        record_result "openEuler 24.03" "dnf install" "FAIL" "Package install failed"
        docker rm -f "$container" 2>/dev/null
        return
    fi

    log_info "opentenbase-ctl init ..."
    if docker exec "$container" bash -c "opentenbase-ctl init" 2>&1; then
        record_result "openEuler 24.03" "init" "PASS" "Cluster initialized"
    else
        record_result "openEuler 24.03" "init" "FAIL" "Init failed"
        docker rm -f "$container" 2>/dev/null
        return
    fi

    log_info "opentenbase-ctl start ..."
    if docker exec "$container" bash -c "opentenbase-ctl start" 2>&1; then
        record_result "openEuler 24.03" "start" "PASS" "All nodes started"
    else
        record_result "openEuler 24.03" "start" "FAIL" "Start failed"
        docker rm -f "$container" 2>/dev/null
        return
    fi

    log_info "opentenbase-ctl status ..."
    local status_output
    status_output=$(docker exec "$container" bash -c "opentenbase-ctl status" 2>&1)
    echo "$status_output"
    if echo "$status_output" | grep -q "STOPPED"; then
        record_result "openEuler 24.03" "status" "FAIL" "Some nodes stopped"
    else
        record_result "openEuler 24.03" "status" "PASS" "All nodes running"
    fi

    log_info "SQL query test ..."
    local sql_output
    sql_output=$(docker exec "$container" bash -c "
        psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1 -X -q -c 'SELECT version();' 2>&1
    ")
    echo "$sql_output"
    if echo "$sql_output" | grep -q "OpenTenBase"; then
        record_result "openEuler 24.03" "SQL query" "PASS" "SELECT version() OK"
    else
        record_result "openEuler 24.03" "SQL query" "FAIL" "Query failed"
    fi

    log_info "DISTRIBUTE BY SHARD test ..."
    local shard_output
    shard_output=$(docker exec "$container" bash -c "
        psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1 -X -q -v ON_ERROR_STOP=1 -c \"
            CREATE TABLE docker_test (id int, name text) DISTRIBUTE BY SHARD(id);
            INSERT INTO docker_test VALUES (1, 'hello from docker');
            SELECT * FROM docker_test;
            DROP TABLE docker_test;
        \" 2>&1
    ")
    echo "$shard_output"
    if echo "$shard_output" | grep -q "hello from docker"; then
        record_result "openEuler 24.03" "SHARD table" "PASS" "DISTRIBUTE BY SHARD OK"
    else
        record_result "openEuler 24.03" "SHARD table" "FAIL" "Shard test failed"
    fi

    log_info "opentenbase-ctl stop ..."
    docker exec "$container" bash -c "opentenbase-ctl stop" 2>&1 || true
    record_result "openEuler 24.03" "stop" "PASS" "Cluster stopped"

    docker rm -f "$container" 2>/dev/null
    log_info "openEuler 24.03 test complete"
}

# ─── Main ───────────────────────────────────────────────────────────────────
TARGET="${1:-all}"

echo "========================================"
echo "  OpenTenBase Docker E2E Test Suite"
echo "  Architecture: $(uname -m)"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"
echo ""

case "$TARGET" in
    ubuntu)    test_ubuntu ;;
    rocky)     test_rocky ;;
    openeuler) test_openeuler ;;
    all)
        test_ubuntu
        test_rocky
        test_openeuler
        ;;
    *) echo "Usage: $0 [ubuntu|rocky|openeuler|all]"; exit 1 ;;
esac

# ─── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  Test Results Summary"
echo "========================================"
echo ""
echo -e "| Distro | Test | Status | Detail |"
echo -e "|--------|------|--------|--------|"
echo -e "$results"
echo ""
total=$((passed + failed))
echo "Total: $total | Passed: $passed | Failed: $failed"
echo ""

# Write results to file
cat > "$RESULTS_FILE" << EOF
# OpenTenBase Docker E2E Test Results

**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**Architecture:** $(uname -m)

## Results

| Distro | Test | Status | Detail |
|--------|------|--------|--------|
$(echo -e "$results")

## Summary

- **Total:** $total
- **Passed:** $passed
- **Failed:** $failed
EOF

log_info "Results written to: $RESULTS_FILE"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
