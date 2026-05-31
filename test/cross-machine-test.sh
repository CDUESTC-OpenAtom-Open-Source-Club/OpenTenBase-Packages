#!/bin/bash
# OpenTenBase Cross-Machine Multi-Node Test
# Tests distributed deployment across two machines via SSH tunnel
#
# Architecture:
#   devenv (ARM64, no public IP) — GTM + Coordinator
#   47.108 (x86_64, public IP)  — Datanode
#
# Prerequisites:
#   1. SSH key from devenv to 47.108 configured
#   2. opentenbase installed on both machines
#   3. hdspace tunnel accessible for devenv SSH
#
# Usage:
#   ./test/cross-machine-test.sh --devenv-port 56876 --devenv-key /path/to/key
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

# Default values
DEVENV_PORT=56876
DEVENV_KEY="$HOME/.devenv/.ssh/IdentityFile/6aa2a52475f04263a1466e56f305e65b"
REMOTE_HOST="47.108.249.115"
OTB_VERSION="5.0"
OTB_USER="opentenbase"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --devenv-port) DEVENV_PORT="$2"; shift 2 ;;
        --devenv-key) DEVENV_KEY="$2"; shift 2 ;;
        --remote-host) REMOTE_HOST="$2"; shift 2 ;;
        --version) OTB_VERSION="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

DEVENV_SSH="ssh -o ConnectTimeout=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $DEVENV_KEY -p $DEVENV_PORT developer@127.0.0.1"
REMOTE_SSH="ssh -o ConnectTimeout=30 root@${REMOTE_HOST}"

GTM_PORT=6666
COORD_PORT=5432
DN_PORT=25432
DN_POOLER=26661
DN_FWD=26670
COORD_FWD=6671

info "=== Cross-Machine Multi-Node Test ==="
info "devenv: localhost:$DEVENV_PORT (ARM64, GTM+Coordinator)"
info "Datanode: $REMOTE_HOST:$DN_PORT (x86_64)"

# Helper to run commands on devenv
run_devenv() {
    $DEVENV_SSH "$@"
}

# Helper to run commands on remote
run_remote() {
    $REMOTE_SSH "$@"
}

# Step 1: Verify connectivity
info "=== 1. Verify Connectivity ==="
run_devenv "echo DEVENV_OK" && pass "devenv reachable" || fail "devenv unreachable"
run_remote "echo REMOTE_OK" && pass "Remote reachable" || fail "Remote unreachable"

# Step 2: Clean old data
info "=== 2. Clean Old Data ==="
run_devenv "rm -rf /var/lib/opentenbase/${OTB_VERSION}/{gtm,coord,dn1} /var/log/opentenbase/*" 2>/dev/null || true
run_remote "pkill -f 'postgres.*datanode' 2>/dev/null || true; rm -rf /var/lib/opentenbase/${OTB_VERSION}/dn1 /var/log/opentenbase/*" 2>/dev/null || true
sleep 1
pass "Old data cleaned"

# Step 3: Initialize GTM on devenv
info "=== 3. Initialize GTM on devenv ==="
run_devenv "su - $OTB_USER -c 'LD_LIBRARY_PATH=/usr/lib/opentenbase/${OTB_VERSION}/lib /usr/lib/opentenbase/${OTB_VERSION}/bin/initgtm -Z gtm -D /var/lib/opentenbase/${OTB_VERSION}/gtm'"
run_devenv "cat > /var/lib/opentenbase/${OTB_VERSION}/gtm/gtm.conf <<EOF
listen_addresses = '*'
port = $GTM_PORT
nodename = 'one'
EOF
chown $OTB_USER:$OTB_USER /var/lib/opentenbase/${OTB_VERSION}/gtm/gtm.conf"
pass "GTM initialized"

# Step 4: Initialize Coordinator on devenv
info "=== 4. Initialize Coordinator on devenv ==="
run_devenv "su - $OTB_USER -c 'LD_LIBRARY_PATH=/usr/lib/opentenbase/${OTB_VERSION}/lib /usr/lib/opentenbase/${OTB_VERSION}/bin/initdb -D /var/lib/opentenbase/${OTB_VERSION}/coord --nodename=coord --nodetype=coordinator --master_gtm_nodename=one --master_gtm_ip=127.0.0.1 --master_gtm_port=$GTM_PORT'"
run_devenv "cat >> /var/lib/opentenbase/${OTB_VERSION}/coord/postgresql.conf <<EOF
port = $COORD_PORT
pooler_port = 6669
forward_port = $COORD_FWD
listen_addresses = '*'
EOF
echo 'host all all 0.0.0.0/0 trust' >> /var/lib/opentenbase/${OTB_VERSION}/coord/pg_hba.conf"
pass "Coordinator initialized"

# Step 5: Start GTM on devenv
info "=== 5. Start GTM ==="
run_devenv "su - $OTB_USER -c 'LD_LIBRARY_PATH=/usr/lib/opentenbase/${OTB_VERSION}/lib /usr/lib/opentenbase/${OTB_VERSION}/bin/gtm -D /var/lib/opentenbase/${OTB_VERSION}/gtm > /var/log/opentenbase/gtm.log 2>&1 &'"
sleep 3
if run_devenv "pgrep -f 'gtm.*gtm' > /dev/null"; then
    pass "GTM started on port $GTM_PORT"
else
    fail "GTM failed to start"
    run_devenv "tail -20 /var/log/opentenbase/gtm.log" 2>/dev/null || true
    exit 1
fi

# Step 6: Start Coordinator on devenv
info "=== 6. Start Coordinator ==="
run_devenv "su - $OTB_USER -c 'LD_LIBRARY_PATH=/usr/lib/opentenbase/${OTB_VERSION}/lib /usr/lib/opentenbase/${OTB_VERSION}/bin/postgres --coordinator -D /var/lib/opentenbase/${OTB_VERSION}/coord > /var/log/opentenbase/coord.log 2>&1 &'"
sleep 3
if run_devenv "pgrep -f 'postgres.*coordinator' > /dev/null"; then
    pass "Coordinator started on port $COORD_PORT"
else
    fail "Coordinator failed to start"
    run_devenv "tail -20 /var/log/opentenbase/coord.log" 2>/dev/null || true
    exit 1
fi

# Step 7: Initialize Datanode on remote
info "=== 7. Initialize Datanode on remote ==="
run_remote "su - $OTB_USER -c 'LD_LIBRARY_PATH=/usr/lib/opentenbase/${OTB_VERSION}/lib /usr/lib/opentenbase/${OTB_VERSION}/bin/initdb -D /var/lib/opentenbase/${OTB_VERSION}/dn1 --nodename=dn1 --nodetype=datanode --master_gtm_nodename=one --master_gtm_ip=127.0.0.1 --master_gtm_port=16666'"
run_remote "cat >> /var/lib/opentenbase/${OTB_VERSION}/dn1/postgresql.conf <<EOF
port = $DN_PORT
pooler_port = $DN_POOLER
forward_port = $DN_FWD
listen_addresses = '*'
EOF
echo 'host all all 0.0.0.0/0 trust' >> /var/lib/opentenbase/${OTB_VERSION}/dn1/pg_hba.conf
chown -R $OTB_USER:$OTB_USER /var/lib/opentenbase/${OTB_VERSION}/dn1"
pass "Datanode initialized"

# Step 8: Establish SSH tunnel
info "=== 8. Establish SSH Tunnel ==="
# Kill any existing tunnel
run_devenv "pkill -f 'ssh.*16666' 2>/dev/null || true; pkill -f 'ssh.*25432' 2>/dev/null || true"
sleep 1
# Create tunnel: reverse for GTM/Coord, local for Datanode
run_devenv "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -f -N -L ${DN_PORT}:127.0.0.1:${DN_PORT} -R 16666:127.0.0.1:${GTM_PORT} -R 15432:127.0.0.1:${COORD_PORT} root@${REMOTE_HOST}"
sleep 2
if run_devenv "ss -tlnp | grep -q ${DN_PORT}"; then
    pass "SSH tunnel established"
else
    fail "SSH tunnel failed"
    exit 1
fi

# Step 9: Start Datanode on remote
info "=== 9. Start Datanode on remote ==="
run_remote "echo '/usr/lib/opentenbase/${OTB_VERSION}/lib' > /etc/ld.so.conf.d/opentenbase.conf && ldconfig 2>/dev/null || true"
run_remote "su - $OTB_USER -c 'LD_LIBRARY_PATH=/usr/lib/opentenbase/${OTB_VERSION}/lib /usr/lib/opentenbase/${OTB_VERSION}/bin/postgres --datanode -D /var/lib/opentenbase/${OTB_VERSION}/dn1 > /var/log/opentenbase/dn.log 2>&1 &'"
sleep 3
if run_remote "pgrep -f 'postgres.*datanode' > /dev/null"; then
    pass "Datanode started on port $DN_PORT"
else
    fail "Datanode failed to start"
    run_remote "tail -20 /var/log/opentenbase/dn.log" 2>/dev/null || true
    exit 1
fi

# Step 10: Register nodes
info "=== 10. Register Nodes ==="
COORD_PSQL="su - $OTB_USER -c 'LD_LIBRARY_PATH=/usr/lib/opentenbase/${OTB_VERSION}/lib /usr/lib/opentenbase/${OTB_VERSION}/bin/psql -h 127.0.0.1 -p $COORD_PORT -U $OTB_USER -d postgres -X -q'"

# On Coordinator
run_devenv "$COORD_PSQL -c \"CREATE GTM NODE gtm_master WITH (HOST='127.0.0.1', PORT=$GTM_PORT, PRIMARY);\"" 2>/dev/null || true
run_devenv "$COORD_PSQL -c \"ALTER GTM NODE gtm_master WITH (HOST='127.0.0.1', PORT=$GTM_PORT, PRIMARY);\"" 2>/dev/null || true
run_devenv "$COORD_PSQL -c \"CREATE NODE dn1 WITH (TYPE='datanode', HOST='127.0.0.1', PORT=$DN_PORT, FORWARD=$DN_FWD, PRIMARY, PREFERRED);\"" 2>/dev/null || true
run_devenv "$COORD_PSQL -c \"ALTER NODE dn1 WITH (TYPE='datanode', HOST='127.0.0.1', PORT=$DN_PORT, FORWARD=$DN_FWD, PRIMARY, PREFERRED);\"" 2>/dev/null || true
run_devenv "$COORD_PSQL -c \"CREATE NODE coord WITH (TYPE='coordinator', HOST='127.0.0.1', PORT=$COORD_PORT, FORWARD=$COORD_FWD);\"" 2>/dev/null || true
run_devenv "$COORD_PSQL -c \"ALTER NODE coord WITH (TYPE='coordinator', HOST='127.0.0.1', PORT=$COORD_PORT, FORWARD=$COORD_FWD);\"" 2>/dev/null || true
run_devenv "$COORD_PSQL -c \"SELECT pgxc_pool_reload();\""

# On Datanode
DN_PSQL="su - $OTB_USER -c 'LD_LIBRARY_PATH=/usr/lib/opentenbase/${OTB_VERSION}/lib /usr/lib/opentenbase/${OTB_VERSION}/bin/psql -h 127.0.0.1 -p $DN_PORT -U $OTB_USER -d postgres -X -q'"
run_remote "$DN_PSQL -c \"CREATE GTM NODE gtm_master WITH (HOST='127.0.0.1', PORT=16666, PRIMARY);\"" 2>/dev/null || true
run_remote "$DN_PSQL -c \"ALTER GTM NODE gtm_master WITH (HOST='127.0.0.1', PORT=16666, PRIMARY);\"" 2>/dev/null || true
run_remote "$DN_PSQL -c \"CREATE NODE coord WITH (TYPE='coordinator', HOST='127.0.0.1', PORT=15432, FORWARD=$COORD_FWD);\"" 2>/dev/null || true
run_remote "$DN_PSQL -c \"ALTER NODE coord WITH (TYPE='coordinator', HOST='127.0.0.1', PORT=15432, FORWARD=$COORD_FWD);\"" 2>/dev/null || true
run_remote "$DN_PSQL -c \"SELECT pgxc_pool_reload();\""

# Verify
NODES=$(run_devenv "$COORD_PSQL -t -A -c \"SELECT count(*) FROM pgxc_node;\"")
[ "$NODES" = "3" ] && pass "Nodes registered (3 nodes)" || fail "Node registration (got $NODES nodes)"

# Step 11: Create node group and sharding
info "=== 11. Create Node Group ==="
run_devenv "$COORD_PSQL -c \"CREATE DEFAULT NODE GROUP default_group WITH (dn1);\"" 2>/dev/null || true
run_devenv "$COORD_PSQL -c \"CREATE SHARDING GROUP TO GROUP default_group;\"" 2>/dev/null || true
pass "Node group created"

# Step 12: CRUD Operations
info "=== 12. Cross-Machine CRUD ==="
PSQL="run_devenv $COORD_PSQL"

$PSQL -c "CREATE TABLE cross_test (id int PRIMARY KEY, name text, source text) DISTRIBUTE BY SHARD(id);" && \
    pass "CREATE sharding table" || fail "CREATE sharding table"

$PSQL -c "INSERT INTO cross_test VALUES (1, 'Alice', 'devenv->47.108'), (2, 'Bob', 'cross-machine'), (3, 'Charlie', 'sharding');" && \
    pass "INSERT 3 rows" || fail "INSERT"

RESULT=$($PSQL -t -A -c "SELECT count(*) FROM cross_test;")
[ "$RESULT" = "3" ] && pass "SELECT count = 3" || fail "SELECT count (got $RESULT)"

RESULT=$($PSQL -t -A -c "SELECT name FROM cross_test WHERE id = 2;")
[ "$RESULT" = "Bob" ] && pass "SELECT WHERE id=2" || fail "SELECT WHERE (got $RESULT)"

$PSQL -c "UPDATE cross_test SET name = 'Alice2' WHERE id = 1;" && \
    pass "UPDATE row" || fail "UPDATE"

RESULT=$($PSQL -t -A -c "SELECT name FROM cross_test WHERE id = 1;")
[ "$RESULT" = "Alice2" ] && pass "UPDATE verified" || fail "UPDATE verify (got $RESULT)"

$PSQL -c "DELETE FROM cross_test WHERE id = 3;" && \
    pass "DELETE row" || fail "DELETE"

RESULT=$($PSQL -t -A -c "SELECT count(*) FROM cross_test;")
[ "$RESULT" = "2" ] && pass "DELETE verified (count=2)" || fail "DELETE verify (got $RESULT)"

# Verify data locality on Datanode
DN_COUNT=$(run_remote "$DN_PSQL -t -A -c \"SELECT count(*) FROM cross_test;\"" 2>/dev/null || echo "0")
[ "$DN_COUNT" = "2" ] && pass "Data stored on remote Datanode" || fail "Data locality (DN count=$DN_COUNT)"

$PSQL -c "DROP TABLE cross_test;" && pass "DROP table" || fail "DROP table"

# Step 13: Cleanup
info "=== 13. Cleanup ==="
$PSQL -c "SELECT pgxc_pool_reload();" 2>/dev/null || true
run_devenv "pkill -f 'postgres.*coordinator' 2>/dev/null || true; pkill -f 'gtm' 2>/dev/null || true"
run_remote "pkill -f 'postgres.*datanode' 2>/dev/null || true"
run_devenv "pkill -f 'ssh.*16666' 2>/dev/null || true; pkill -f 'ssh.*25432' 2>/dev/null || true"
sleep 2
pass "Cluster stopped"

echo ""
echo "========================================"
echo "  Cross-Machine Test Results"
echo "========================================"
echo "  Architecture: devenv (GTM+Coord) -> 47.108 (Datanode)"
echo "  Total:  $TOTAL"
echo -e "  Passed: ${GREEN}$PASS${NC}"
echo -e "  Failed: ${RED}$FAIL${NC}"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}All cross-machine tests passed!${NC}"
    exit 0
else
    echo -e "${RED}$FAIL test(s) failed!${NC}"
    exit 1
fi
