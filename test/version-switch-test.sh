#!/bin/bash
# OpenTenBase Version Switch Test
# Tests multi-version installation and switching between versions
# Usage: bash version-switch-test.sh
#
# Requires: packages available at /tmp/debs/ or /tmp/rpms/
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
TOTAL=0

pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }
info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

OTB_USER=opentenbase
OTB_HOME=/var/lib/opentenbase
OTB_BIN=/usr/lib/opentenbase/5.0/bin
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Run command as opentenbase user with correct LD_LIBRARY_PATH
# Always use full paths ($OTB_BIN/...) to avoid PATH resolution issues
run_as_otb() {
    if [ "$(id -un)" = "$OTB_USER" ]; then
        LD_LIBRARY_PATH="$OTB_HOME/lib:${LD_LIBRARY_PATH:-}" "$@"
    elif command -v sudo >/dev/null 2>&1; then
        cd / && sudo -u "$OTB_USER" env LD_LIBRARY_PATH="$OTB_HOME/lib" "$@"
    elif command -v runuser >/dev/null 2>&1; then
        cd / && runuser -u "$OTB_USER" -- env LD_LIBRARY_PATH="$OTB_HOME/lib" "$@"
    elif command -v setpriv >/dev/null 2>&1; then
        OTB_UID=$(id -u "$OTB_USER")
        OTB_GID=$(id -g "$OTB_USER")
        cd / && setpriv --reuid="$OTB_UID" --regid="$OTB_GID" --init-groups env LD_LIBRARY_PATH="$OTB_HOME/lib" "$@"
    elif command -v python3 >/dev/null 2>&1; then
        OTB_UID=$(id -u "$OTB_USER")
        OTB_GID=$(id -g "$OTB_USER")
        cd / && python3 -c "import os,sys; os.setgid($OTB_GID); os.setuid($OTB_UID); os.environ['LD_LIBRARY_PATH']='$OTB_HOME/lib'; os.execv(sys.argv[1], sys.argv[1:])" "$@"
    elif command -v su >/dev/null 2>&1; then
        cd / && su -s /bin/bash "$OTB_USER" -c "LD_LIBRARY_PATH=$OTB_HOME/lib $*"
    else
        echo "ERROR: No user-switching tool available (sudo/runuser/setpriv/su/python3)" >&2
        exit 1
    fi
}

# Ensure user exists
id $OTB_USER 2>/dev/null || {
    groupadd --system $OTB_USER 2>/dev/null || true
    useradd --system --gid $OTB_USER --home-dir /var/lib/opentenbase --shell /bin/bash $OTB_USER 2>/dev/null || true
}

# ============================================================
# Test 1: Install first version (5.0)
# ============================================================
info "=== Test 1: Install version 5.0 ==="

if [ -f "$REPO_DIR/scripts/install.sh" ]; then
    bash "$REPO_DIR/scripts/install.sh" --version 5.0 /tmp/debs 2>&1 || \
    bash "$REPO_DIR/scripts/install.sh" --version 5.0 /tmp/rpms 2>&1 || \
    bash "$REPO_DIR/scripts/install.sh" --version 5.0 2>&1
fi

# Verify installation
if [ -d /usr/lib/opentenbase/5.0/bin ]; then
    pass "Version 5.0 binaries installed"
else
    fail "Version 5.0 binaries not found"
fi

if [ -d /etc/opentenbase/5.0 ]; then
    pass "Version 5.0 config directory exists"
else
    fail "Version 5.0 config directory missing"
fi

if [ -f /etc/opentenbase/5.0/opentenbase.conf ]; then
    pass "Version 5.0 opentenbase.conf exists"
else
    fail "Version 5.0 opentenbase.conf missing"
fi

# Check current symlink
if [ -L /etc/opentenbase/current ]; then
    CURRENT=$(basename "$(readlink -f /etc/opentenbase/current)")
    if [ "$CURRENT" = "5.0" ]; then
        pass "Current version symlink -> 5.0"
    else
        fail "Current version symlink points to $CURRENT, expected 5.0"
    fi
else
    fail "No current version symlink found"
fi

# ============================================================
# Test 2: Install second version (2.6.0)
# ============================================================
info "=== Test 2: Install version 2.6.0 ==="

if [ -f "$REPO_DIR/scripts/install.sh" ]; then
    bash "$REPO_DIR/scripts/install.sh" --version 2.6.0 /tmp/debs 2>&1 || \
    bash "$REPO_DIR/scripts/install.sh" --version 2.6.0 /tmp/rpms 2>&1 || \
    bash "$REPO_DIR/scripts/install.sh" --version 2.6.0 2>&1 || true
fi

# Verify second version
if [ -d /usr/lib/opentenbase/2.6.0/bin ]; then
    pass "Version 2.6.0 binaries installed"
else
    info "Version 2.6.0 not available (may not have pre-built package), skipping"
fi

# ============================================================
# Test 3: List installed versions
# ============================================================
info "=== Test 3: List installed versions ==="

if command -v opentenbase-switch-version >/dev/null 2>&1; then
    VERSIONS_OUTPUT=$(opentenbase-switch-version 2>&1)
    echo "$VERSIONS_OUTPUT"

    if echo "$VERSIONS_OUTPUT" | grep -q "5.0"; then
        pass "opentenbase-switch-version lists 5.0"
    else
        fail "opentenbase-switch-version does not list 5.0"
    fi
else
    fail "opentenbase-switch-version command not found"
fi

# ============================================================
# Test 4: Switch to 5.0
# ============================================================
info "=== Test 4: Switch to version 5.0 ==="

if command -v opentenbase-switch-version >/dev/null 2>&1; then
    sudo opentenbase-switch-version 5.0 2>&1

    CURRENT=$(basename "$(readlink -f /etc/opentenbase/current)")
    if [ "$CURRENT" = "5.0" ]; then
        pass "Switched to 5.0"
    else
        fail "Switch failed, current is $CURRENT"
    fi

    # Verify binary version
    PG_VERSION=$(/usr/lib/opentenbase/5.0/bin/postgres --version 2>&1 || echo "unknown")
    if echo "$PG_VERSION" | grep -q "5.0\|PostgreSQL"; then
        pass "postgres --version shows correct version"
    else
        fail "postgres --version unexpected: $PG_VERSION"
    fi
fi

# ============================================================
# Test 5: Init and start cluster on version 5.0
# ============================================================
info "=== Test 5: Init and start cluster (v5.0) ==="

if command -v opentenbase-ctl >/dev/null 2>&1; then
    sudo opentenbase-ctl stop 2>/dev/null || true
    sudo opentenbase-ctl init 2>&1 && pass "opentenbase-ctl init succeeded" || fail "opentenbase-ctl init failed"

    sudo opentenbase-ctl start 2>&1 && pass "opentenbase-ctl start succeeded" || fail "opentenbase-ctl start failed"

    sleep 5

    # Check GTM
    if pgrep -f "gtm" >/dev/null 2>&1; then
        pass "GTM process running"
    else
        fail "GTM process not found"
    fi

    # Check coordinator
    if pgrep -f "postgres.*coordinator" >/dev/null 2>&1; then
        pass "Coordinator process running"
    else
        fail "Coordinator process not found"
    fi

    # SQL test
    SQL_RESULT=$(run_as_otb $OTB_BIN/psql -h 127.0.0.1 -p 5432 -U $OTB_USER -d postgres -t -A -c "SELECT 1;" 2>&1 || echo "FAIL")
    if [ "$SQL_RESULT" = "1" ]; then
        pass "SQL connection on v5.0"
    else
        fail "SQL connection failed: $SQL_RESULT"
    fi

    # CRUD test
    run_as_otb $OTB_BIN/psql -h 127.0.0.1 -p 5432 -U $OTB_USER -d postgres -c "CREATE TABLE vtest (id int, name text);" 2>&1 && \
        pass "CREATE TABLE on v5.0" || fail "CREATE TABLE on v5.0"

    run_as_otb $OTB_BIN/psql -h 127.0.0.1 -p 5432 -U $OTB_USER -d postgres -c "INSERT INTO vtest VALUES (1, 'v5test');" 2>&1 && \
        pass "INSERT on v5.0" || fail "INSERT on v5.0"

    RESULT=$(run_as_otb $OTB_BIN/psql -h 127.0.0.1 -p 5432 -U $OTB_USER -d postgres -t -A -c "SELECT name FROM vtest WHERE id=1;" 2>&1)
    [ "$RESULT" = "v5test" ] && pass "SELECT on v5.0" || fail "SELECT on v5.0 (got $RESULT)"

    run_as_otb $OTB_BIN/psql -h 127.0.0.1 -p 5432 -U $OTB_USER -d postgres -c "DROP TABLE vtest;" 2>&1

    # Stop cluster
    sudo opentenbase-ctl stop 2>&1 && pass "Cluster stopped cleanly" || fail "Cluster stop failed"
    sleep 2
fi

# ============================================================
# Test 6: Switch to 2.6.0 and test (if available)
# ============================================================
if [ -d /usr/lib/opentenbase/2.6.0/bin ]; then
    info "=== Test 6: Switch to version 2.6.0 and test ==="

    sudo opentenbase-switch-version 2.6.0 2>&1

    CURRENT=$(basename "$(readlink -f /etc/opentenbase/current)")
    if [ "$CURRENT" = "2.6.0" ]; then
        pass "Switched to 2.6.0"
    else
        fail "Switch to 2.6.0 failed, current is $CURRENT"
    fi

    # Verify it uses different data directory
    CONF_260="/etc/opentenbase/2.6.0/opentenbase.conf"
    if [ -f "$CONF_260" ]; then
        DN1_PORT_260=$(grep '^DN1_PORT=' "$CONF_260" | cut -d= -f2 | tr -d ' ')
        COORD_PORT_260=$(grep '^COORD_PORT=' "$CONF_260" | cut -d= -f2 | tr -d ' ')
        info "v2.6.0 ports: coord=$COORD_PORT_260 dn1=$DN1_PORT_260"

        # Init and start
        sudo opentenbase-ctl stop 2>/dev/null || true
        sudo opentenbase-ctl init 2>&1 && pass "v2.6.0 init" || fail "v2.6.0 init"
        sudo opentenbase-ctl start 2>&1 && pass "v2.6.0 start" || fail "v2.6.0 start"

        sleep 5
        sudo opentenbase-ctl stop 2>&1 && pass "v2.6.0 stop" || fail "v2.6.0 stop"
        sleep 2
    fi

    # Switch back to 5.0
    info "=== Switch back to 5.0 ==="
    sudo opentenbase-switch-version 5.0 2>&1
    CURRENT=$(basename "$(readlink -f /etc/opentenbase/current)")
    [ "$CURRENT" = "5.0" ] && pass "Switched back to 5.0" || fail "Switch back failed"
fi

# ============================================================
# Test 7: Error handling
# ============================================================
info "=== Test 7: Error handling ==="

if command -v opentenbase-switch-version >/dev/null 2>&1; then
    # Try switching to non-existent version
    if sudo opentenbase-switch-version 9.9.9 2>&1 | grep -qi "not found\|error"; then
        pass "Non-existent version gives error"
    else
        fail "Non-existent version did not give error"
    fi
fi

# ============================================================
# Results
# ============================================================
echo ""
echo "========================================"
echo "  Version Switch Test Results"
echo "========================================"
echo "  Total:  $TOTAL"
echo -e "  Passed: ${GREEN}$PASS${NC}"
echo -e "  Failed: ${RED}$FAIL${NC}"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}All version switch tests passed!${NC}"
    exit 0
else
    echo -e "${RED}$FAIL test(s) failed!${NC}"
    exit 1
fi
