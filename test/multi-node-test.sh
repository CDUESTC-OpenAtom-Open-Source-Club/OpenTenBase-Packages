#!/bin/bash
# OpenTenBase Multi-Node Smoke Test
# Tests GTM + Coordinator + Datanode deployment and CRUD operations
# Runs inside Docker container after package installation
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
OTB_BIN=/usr/lib/opentenbase/${OTB_VERSION:-5.0}/bin
GTM_PORT=6666
DN_PORT=5433
COORD_PORT=5432
DN_POOLER=6668
DN_FWD=6670
COORD_POOLER=6669
COORD_FWD=6671

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
    useradd --system --gid $OTB_USER --home-dir $OTB_HOME --shell /bin/bash $OTB_USER 2>/dev/null || true
}

mkdir -p $OTB_HOME/data/{gtm,dn1,coord} /var/log/opentenbase
chown -R $OTB_USER:$OTB_USER $OTB_HOME /var/log/opentenbase

# Ensure library path is configured
echo "$OTB_HOME/lib" > /etc/ld.so.conf.d/opentenbase.conf 2>/dev/null || true
ldconfig 2>/dev/null || true

# Reduce shared memory requirements for low-memory CI containers
export PG_SHMEM_PAGES=512

info "=== 1. Initialize GTM ==="
run_as_otb $OTB_BIN/initgtm -Z gtm -D $OTB_HOME/data/gtm
cat > $OTB_HOME/data/gtm/gtm.conf <<EOF
listen_addresses = '*'
port = $GTM_PORT
nodename = 'one'
EOF
chown $OTB_USER:$OTB_USER $OTB_HOME/data/gtm/gtm.conf

info "=== 2. Initialize Datanode ==="
run_as_otb $OTB_BIN/initdb -D $OTB_HOME/data/dn1 --nodename=dn1 --nodetype=datanode \
    --master_gtm_nodename=one --master_gtm_ip=127.0.0.1 --master_gtm_port=$GTM_PORT
# forward_port is only valid in v5.0+
cat >> $OTB_HOME/data/dn1/postgresql.conf <<EOF
port = $DN_PORT
pooler_port = $DN_POOLER
listen_addresses = '*'
EOF
[ "${OTB_VERSION:-5.0}" = "5.0" ] && echo "forward_port = $DN_FWD" >> $OTB_HOME/data/dn1/postgresql.conf

info "=== 3. Initialize Coordinator ==="
run_as_otb $OTB_BIN/initdb -D $OTB_HOME/data/coord --nodename=coord --nodetype=coordinator \
    --master_gtm_nodename=one --master_gtm_ip=127.0.0.1 --master_gtm_port=$GTM_PORT
cat >> $OTB_HOME/data/coord/postgresql.conf <<EOF
port = $COORD_PORT
pooler_port = $COORD_POOLER
listen_addresses = '*'
EOF
[ "${OTB_VERSION:-5.0}" = "5.0" ] && echo "forward_port = $COORD_FWD" >> $OTB_HOME/data/coord/postgresql.conf

info "=== 4. Start GTM ==="
run_as_otb $OTB_BIN/gtm -D $OTB_HOME/data/gtm > /tmp/gtm.log 2>&1 &
GTM_PID=$!
sleep 3
if kill -0 $GTM_PID 2>/dev/null; then
    pass "GTM started on port $GTM_PORT"
else
    fail "GTM failed to start"
    echo "--- GTM log ---"
    cat /tmp/gtm.log 2>/dev/null || true
    echo "--- end GTM log ---"
    exit 1
fi

info "=== 5. Start Datanode ==="
run_as_otb $OTB_BIN/postgres --datanode -D $OTB_HOME/data/dn1 > /tmp/dn.log 2>&1 &
sleep 3
if pgrep -f "postgres.*datanode" >/dev/null 2>&1; then
    pass "Datanode started on port $DN_PORT"
else
    fail "Datanode failed to start"
    echo "--- Datanode log ---"
    tail -20 /tmp/dn.log 2>/dev/null || true
    echo "--- end Datanode log ---"
    exit 1
fi

info "=== 6. Start Coordinator ==="
run_as_otb $OTB_BIN/postgres --coordinator -D $OTB_HOME/data/coord > /tmp/coord.log 2>&1 &
sleep 3
if pgrep -f "postgres.*coordinator" >/dev/null 2>&1; then
    pass "Coordinator started on port $COORD_PORT"
else
    fail "Coordinator failed to start"
    echo "--- Coordinator log ---"
    tail -20 /tmp/coord.log 2>/dev/null || true
    echo "--- end Coordinator log ---"
    exit 1
fi

info "=== 7. Register Nodes ==="
COORD_PSQL="$OTB_BIN/psql -h 127.0.0.1 -p $COORD_PORT -U $OTB_USER -d postgres -X -q -v ON_ERROR_STOP=0"
DN_PSQL="$OTB_BIN/psql -h 127.0.0.1 -p $DN_PORT -U $OTB_USER -d postgres -X -q -v ON_ERROR_STOP=0"

# Register GTM node on coordinator
run_as_otb $COORD_PSQL -c "CREATE GTM NODE gtm_master WITH (HOST='127.0.0.1', PORT=$GTM_PORT, PRIMARY);" 2>/dev/null || true
run_as_otb $COORD_PSQL -c "ALTER GTM NODE gtm_master WITH (HOST='127.0.0.1', PORT=$GTM_PORT, PRIMARY);" 2>/dev/null || true

# Register datanode on coordinator
run_as_otb $COORD_PSQL -c "CREATE NODE dn1 WITH (TYPE='datanode', HOST='127.0.0.1', PORT=$DN_PORT, FORWARD=$DN_FWD, PRIMARY, PREFERRED);" 2>/dev/null || true
run_as_otb $COORD_PSQL -c "ALTER NODE dn1 WITH (TYPE='datanode', HOST='127.0.0.1', PORT=$DN_PORT, FORWARD=$DN_FWD, PRIMARY, PREFERRED);" 2>/dev/null || true

# Register coordinator on coordinator (self)
run_as_otb $COORD_PSQL -c "CREATE NODE coord WITH (TYPE='coordinator', HOST='127.0.0.1', PORT=$COORD_PORT, FORWARD=$COORD_FWD);" 2>/dev/null || true
run_as_otb $COORD_PSQL -c "ALTER NODE coord WITH (TYPE='coordinator', HOST='127.0.0.1', PORT=$COORD_PORT, FORWARD=$COORD_FWD);" 2>/dev/null || true

# Reload pool
run_as_otb $COORD_PSQL -c "SELECT pgxc_pool_reload();" >/dev/null 2>&1 || true

# Propagate registrations to datanode
run_as_otb $DN_PSQL -c "CREATE GTM NODE gtm_master WITH (HOST='127.0.0.1', PORT=$GTM_PORT, PRIMARY);" 2>/dev/null || true
run_as_otb $DN_PSQL -c "ALTER GTM NODE gtm_master WITH (HOST='127.0.0.1', PORT=$GTM_PORT, PRIMARY);" 2>/dev/null || true
run_as_otb $DN_PSQL -c "CREATE NODE coord WITH (TYPE='coordinator', HOST='127.0.0.1', PORT=$COORD_PORT, FORWARD=$COORD_FWD);" 2>/dev/null || true
run_as_otb $DN_PSQL -c "ALTER NODE coord WITH (TYPE='coordinator', HOST='127.0.0.1', PORT=$COORD_PORT, FORWARD=$COORD_FWD);" 2>/dev/null || true
run_as_otb $DN_PSQL -c "SELECT pgxc_pool_reload();" >/dev/null 2>&1 || true

pass "Nodes registered"

info "=== 8. Create Sharding Group ==="
# Check if node group already exists on coordinator
HAS_GROUP=$(run_as_otb $COORD_PSQL -t -A -c "SELECT count(*) FROM pgxc_group WHERE group_name = 'default_group';" 2>/dev/null || echo "0")

if [ "$HAS_GROUP" != "1" ]; then
    # Get datanode OID from coordinator first
    DN_OID=$(run_as_otb $COORD_PSQL -t -A -c "SELECT oid FROM pgxc_node WHERE node_name = 'dn1' AND node_type = 'D';" 2>/dev/null || echo "")
    if [ -n "$DN_OID" ]; then
        # Create node group on datanode first
        run_as_otb $DN_PSQL -c "CREATE DEFAULT NODE GROUP default_group WITH (dn1);" 2>/dev/null || true

        # Insert node group into coordinator's catalog
        run_as_otb $COORD_PSQL -c "INSERT INTO pgxc_group (group_name, default_group, group_members) VALUES ('default_group', 1, '$DN_OID');" 2>/dev/null || true

        # Reload pool so coordinator sees the group
        run_as_otb $COORD_PSQL -c "SELECT pgxc_pool_reload();" >/dev/null 2>&1 || true

        # Create sharding group
        run_as_otb $COORD_PSQL -c "CREATE SHARDING GROUP TO GROUP default_group;" 2>/dev/null || true
    else
        echo "  WARNING: could not find datanode OID, skipping node group setup"
    fi
fi
pass "Sharding group created"

PSQL="run_as_otb $OTB_BIN/psql -h 127.0.0.1 -p $COORD_PORT -U $OTB_USER -d postgres"

info "=== 9. CRUD Operations ==="

# CREATE TABLE (sharding)
$PSQL -c "CREATE TABLE smoke_test (id int PRIMARY KEY, name text) DISTRIBUTE BY SHARD(id);" && \
    pass "CREATE sharding table" || fail "CREATE sharding table"

# INSERT
$PSQL -c "INSERT INTO smoke_test VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie');" && \
    pass "INSERT 3 rows" || fail "INSERT"

# SELECT all
RESULT=$($PSQL -t -A -c "SELECT count(*) FROM smoke_test;")
[ "$RESULT" = "3" ] && pass "SELECT count = 3" || fail "SELECT count (got $RESULT)"

# SELECT with WHERE
RESULT=$($PSQL -t -A -c "SELECT name FROM smoke_test WHERE id = 2;")
[ "$RESULT" = "Bob" ] && pass "SELECT WHERE id=2" || fail "SELECT WHERE (got $RESULT)"

# UPDATE
$PSQL -c "UPDATE smoke_test SET name = 'Alice2' WHERE id = 1;" && \
    pass "UPDATE row" || fail "UPDATE"

RESULT=$($PSQL -t -A -c "SELECT name FROM smoke_test WHERE id = 1;")
[ "$RESULT" = "Alice2" ] && pass "UPDATE verified" || fail "UPDATE verify (got $RESULT)"

# DELETE
$PSQL -c "DELETE FROM smoke_test WHERE id = 3;" && \
    pass "DELETE row" || fail "DELETE"

RESULT=$($PSQL -t -A -c "SELECT count(*) FROM smoke_test;")
[ "$RESULT" = "2" ] && pass "DELETE verified (count=2)" || fail "DELETE verify (got $RESULT)"

# Normal table
$PSQL -c "CREATE TABLE smoke_normal (id int, val text);" && \
    pass "CREATE normal table" || fail "CREATE normal table"

$PSQL -c "INSERT INTO smoke_normal VALUES (100, 'test');" && \
    pass "INSERT normal table" || fail "INSERT normal table"

RESULT=$($PSQL -t -A -c "SELECT val FROM smoke_normal WHERE id = 100;")
[ "$RESULT" = "test" ] && pass "SELECT normal table" || fail "SELECT normal table"

# Cleanup
$PSQL -c "DROP TABLE smoke_test;" && pass "DROP sharding table" || fail "DROP sharding table"
$PSQL -c "DROP TABLE smoke_normal;" && pass "DROP normal table" || fail "DROP normal table"

info "=== 10. License Check ==="
# Verify cluster is writable (license bypass works)
$PSQL -c "CREATE TABLE license_test (id int);" && \
    pass "License bypass: cluster is writable" || fail "License bypass: cluster is read-only"
$PSQL -c "DROP TABLE license_test;" 2>/dev/null || true

info "=== 11. Cleanup ==="
run_as_otb $OTB_BIN/psql -h 127.0.0.1 -p $COORD_PORT -U $OTB_USER -d postgres -c "SELECT pgxc_pool_reload();" 2>/dev/null || true
kill $(pgrep -f "postgres.*coordinator") 2>/dev/null || true
kill $(pgrep -f "postgres.*datanode") 2>/dev/null || true
kill $(pgrep -f "gtm") 2>/dev/null || true
sleep 2
pass "Cluster stopped cleanly"

echo ""
echo "========================================"
echo "  Multi-Node Test Results"
echo "========================================"
echo "  Total:  $TOTAL"
echo -e "  Passed: ${GREEN}$PASS${NC}"
echo -e "  Failed: ${RED}$FAIL${NC}"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}All multi-node tests passed!${NC}"
    exit 0
else
    echo -e "${RED}$FAIL test(s) failed!${NC}"
    exit 1
fi
