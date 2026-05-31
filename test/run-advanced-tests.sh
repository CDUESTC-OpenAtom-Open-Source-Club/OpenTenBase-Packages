#!/usr/bin/env bash
# =============================================================================
# OpenTenBase Advanced Test Runner
# =============================================================================
# Starts a cluster, runs all advanced test suites, then tears down.
# Uses gtm_ctl/pg_ctl with nohup setsid to ensure processes persist.
# =============================================================================
set -e

BIN_DIR="/usr/lib/opentenbase/${OTB_VERSION:-5.0}/bin"
TEST_BASE="/tmp/otb-adv-test"
GTM_DATA="${TEST_BASE}/gtm"
COORD_DATA="${TEST_BASE}/coord"
DN_DATA="${TEST_BASE}/dn1"
LOG_DIR="${TEST_BASE}/logs"
GTM_PORT=6666
COORD_PORT=5432
DN_PORT=15432
STARTUP_TIMEOUT=30

log() { echo "[adv-test] $(date '+%H:%M:%S') $*"; }
fail() {
    echo "[adv-test] FAIL: $*" >&2
    echo "--- GTM log (last 10) ---" >&2
    tail -10 "${LOG_DIR}/gtm.log" 2>/dev/null >&2 || true
    echo "--- DN log (last 10) ---" >&2
    tail -10 "${LOG_DIR}/dn1.log" 2>/dev/null >&2 || true
    echo "--- Coord log (last 10) ---" >&2
    tail -10 "${LOG_DIR}/coord.log" 2>/dev/null >&2 || true
    stop_services 2>/dev/null
    rm -rf "${TEST_BASE}" 2>/dev/null
    exit 1
}

check_port() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then ss -tlnp 2>/dev/null | grep -q ":${port} "
    elif command -v netstat >/dev/null 2>&1; then netstat -tlnp 2>/dev/null | grep -q ":${port} "
    else (echo >/dev/tcp/127.0.0.1/"${port}") 2>/dev/null; fi
}

wait_for_port() {
    local port="$1" timeout="$2" elapsed=0
    while ! check_port "${port}"; do
        [ "${elapsed}" -ge "${timeout}" ] && return 1
        sleep 1; elapsed=$((elapsed + 1))
    done
}

# Wait for a port to become free (not listening)
wait_for_port_free() {
    local port="$1" timeout="$2" elapsed=0
    while check_port "${port}"; do
        [ "${elapsed}" -ge "${timeout}" ] && return 1
        sleep 1; elapsed=$((elapsed + 1))
    done
}

stop_services() {
    pkill -f "gtm -D ${GTM_DATA}" 2>/dev/null || true
    pkill -f "postgres.*datanode.*${DN_DATA}" 2>/dev/null || true
    pkill -f "postgres.*coordinator.*${COORD_DATA}" 2>/dev/null || true
    # Also kill any leftover postgres/gtm processes from previous test runs
    pkill -f "postgres.*-D" 2>/dev/null || true
    pkill -f "gtm.*-D" 2>/dev/null || true
    sleep 2
}

# Root check
[ "$(id -u)" -eq 0 ] || { log "Not root, re-executing with sudo..."; exec sudo "$0" "$@"; }

# Resolve service user
SVC_USER=""
if id opentenbase >/dev/null 2>&1; then SVC_USER="opentenbase"
elif id postgres >/dev/null 2>&1; then SVC_USER="postgres"
else
    if command -v useradd >/dev/null 2>&1; then useradd -r -s /bin/bash -d "${TEST_BASE}" otbtest 2>/dev/null || true
    elif command -v adduser >/dev/null 2>&1; then adduser -S -s /bin/bash -h "${TEST_BASE}" otbtest 2>/dev/null || true; fi
    SVC_USER="otbtest"
fi
log "Service user: ${SVC_USER}"

as_svc() { su -s /bin/bash -c "$1" "${SVC_USER}"; }
append_conf() { local f="$1"; shift; printf '%s\n' "$@" >> "${f}"; }

# Kill any existing processes (including from previous test runs)
stop_services

# Ensure our ports are free before starting
for port in ${GTM_PORT} ${DN_PORT} ${COORD_PORT}; do
    if check_port "${port}"; then
        log "Port ${port} still in use, waiting for it to be free..."
        if ! wait_for_port_free "${port}" 10; then
            log "Force killing processes on port ${port}..."
            if command -v fuser >/dev/null 2>&1; then
                fuser -k "${port}/tcp" 2>/dev/null || true
            fi
            if command -v ss >/dev/null 2>&1; then
                ss -tlnp | grep ":${port} " | grep -oP 'pid=\K[0-9]+' | xargs -r kill -9 2>/dev/null || true
            fi
            sleep 2
        fi
    fi
done

# Prepare directories
rm -rf "${TEST_BASE}"
mkdir -p "${GTM_DATA}" "${COORD_DATA}" "${DN_DATA}" "${LOG_DIR}"
chown "${SVC_USER}:${SVC_USER}" "${TEST_BASE}" "${GTM_DATA}" "${COORD_DATA}" "${DN_DATA}" "${LOG_DIR}"

# Initialize and start GTM
log "Starting GTM..."
as_svc "${BIN_DIR}/initgtm -D ${GTM_DATA} -Z gtm" || fail "initgtm failed"

# Start GTM using nohup+setsid so process persists when su exits
as_svc "nohup setsid ${BIN_DIR}/gtm -D ${GTM_DATA} > ${LOG_DIR}/gtm.log 2>&1 &" || true
if ! wait_for_port "${GTM_PORT}" "${STARTUP_TIMEOUT}"; then
    fail "GTM not listening on port ${GTM_PORT} within ${STARTUP_TIMEOUT}s"
fi
log "GTM up on port ${GTM_PORT}"

# Initialize and start Datanode
log "Starting Datanode..."
as_svc "${BIN_DIR}/initdb -D ${DN_DATA} --nodename=dn1 --nodetype=datanode --master_gtm_nodename=one --master_gtm_ip=127.0.0.1 --master_gtm_port=${GTM_PORT}" || fail "Datanode initdb failed"
# forward_port is only valid in v5.0+
append_conf "${DN_DATA}/postgresql.conf" \
    "port = ${DN_PORT}" "pooler_port = 6661" \
    "listen_addresses = '*'"
[ "${OTB_VERSION:-5.0}" = "5.0" ] && echo "forward_port = 6670" >> "${DN_DATA}/postgresql.conf"
cat > "${DN_DATA}/pg_hba.conf" <<HBA
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
HBA
chown "${SVC_USER}:${SVC_USER}" "${DN_DATA}/postgresql.conf" "${DN_DATA}/pg_hba.conf"

as_svc "nohup setsid ${BIN_DIR}/postgres --datanode -D ${DN_DATA} > ${LOG_DIR}/dn1.log 2>&1 &" || true
if ! wait_for_port "${DN_PORT}" "${STARTUP_TIMEOUT}"; then
    fail "Datanode not listening on port ${DN_PORT} within ${STARTUP_TIMEOUT}s"
fi
log "Datanode up on port ${DN_PORT}"

# Initialize and start Coordinator
log "Starting Coordinator..."
as_svc "${BIN_DIR}/initdb -D ${COORD_DATA} --nodename=coord --nodetype=coordinator --master_gtm_nodename=one --master_gtm_ip=127.0.0.1 --master_gtm_port=${GTM_PORT}" || fail "Coordinator initdb failed"
append_conf "${COORD_DATA}/postgresql.conf" \
    "port = ${COORD_PORT}" "pooler_port = 6662" \
    "listen_addresses = '*'"
[ "${OTB_VERSION:-5.0}" = "5.0" ] && echo "forward_port = 6669" >> "${COORD_DATA}/postgresql.conf"
cat > "${COORD_DATA}/pg_hba.conf" <<HBA
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
HBA
chown "${SVC_USER}:${SVC_USER}" "${COORD_DATA}/postgresql.conf" "${COORD_DATA}/pg_hba.conf"

as_svc "nohup setsid ${BIN_DIR}/postgres --coordinator -D ${COORD_DATA} > ${LOG_DIR}/coord.log 2>&1 &" || true
if ! wait_for_port "${COORD_PORT}" "${STARTUP_TIMEOUT}"; then
    fail "Coordinator not listening on port ${COORD_PORT} within ${STARTUP_TIMEOUT}s"
fi
log "Coordinator up on port ${COORD_PORT}"

# Register nodes
log "Registering nodes..."
COORD_PSQL="${BIN_DIR}/psql -h 127.0.0.1 -p ${COORD_PORT} -U ${SVC_USER} -d postgres -X -q"
DN_PSQL="${BIN_DIR}/psql -h 127.0.0.1 -p ${DN_PORT} -U ${SVC_USER} -d postgres -X -q"

as_svc "${COORD_PSQL} -c \"CREATE GTM NODE gtm_master WITH (HOST='127.0.0.1', PORT=${GTM_PORT}, PRIMARY);\"" || true
as_svc "${COORD_PSQL} -c \"CREATE NODE dn1 WITH (TYPE='datanode', HOST='127.0.0.1', PORT=${DN_PORT}, FORWARD=6670, PRIMARY, PREFERRED);\"" || true
as_svc "${DN_PSQL} -c \"CREATE GTM NODE gtm_master WITH (HOST='127.0.0.1', PORT=${GTM_PORT}, PRIMARY);\"" || true
as_svc "${DN_PSQL} -c \"CREATE NODE coord WITH (TYPE='coordinator', HOST='127.0.0.1', PORT=${COORD_PORT}, FORWARD=6669);\"" || true

# Create default node group
log "Creating default node group..."
as_svc "${COORD_PSQL} -c \"CREATE DEFAULT NODE GROUP default_group WITH (dn1);\"" || \
as_svc "${COORD_PSQL} -c \"CREATE NODE GROUP default_group WITH (dn1);\"" || true

# Initialize sharding map for the default group
# This is required before any 'distribute by shard()' tables can be created.
# The SQL syntax is: CREATE SHARDING GROUP TO GROUP <group_name>
log "Initializing sharding map..."
as_svc "${COORD_PSQL} -c \"CREATE SHARDING GROUP TO GROUP default_group;\"" 2>&1 || true

as_svc "${COORD_PSQL} -c \"SELECT pgxc_pool_reload();\"" || true
as_svc "${DN_PSQL} -c \"SELECT pgxc_pool_reload();\"" || true
log "Nodes registered"

# Verify sharding map is initialized
log "Verifying sharding map..."
SHARD_CHECK=$(as_svc "${COORD_PSQL} -t -A -c \"SELECT count(*) FROM pgxc_shard_map;\"" 2>&1) || true
log "Shard map entries: ${SHARD_CHECK}"
if [ "${SHARD_CHECK}" = "0" ] || [ -z "${SHARD_CHECK}" ]; then
    log "WARNING: Sharding map appears empty, distributed tables may fail"
fi

# Quick sanity check - try a simple distributed table
log "Sanity check: creating test distributed table..."
if as_svc "${COORD_PSQL} -c \"CREATE TABLE _adv_sanity_check (id int) distribute by shard(id);\""; then
    log "Sanity check: PASSED"
    as_svc "${COORD_PSQL} -c \"DROP TABLE _adv_sanity_check;\"" || true
else
    log "Sanity check: FAILED - distributed tables not working"
    # Show coordinator log for debugging
    tail -20 "${LOG_DIR}/coord.log" 2>/dev/null || true
fi

# Run advanced tests as SVC_USER so psql connects with the correct role
export PATH="/usr/lib/opentenbase/${OTB_VERSION:-5.0}/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0

for test_script in "${SCRIPT_DIR}"/advanced/test_*.sh; do
    [ -f "$test_script" ] || continue
    test_name=$(basename "$test_script" .sh)
    log "Running ${test_name}..."
    # Run each test script as the service user so psql connects with the correct database role
    if timeout --kill-after=10 300 su -s /bin/bash -c "PATH=/usr/lib/opentenbase/${OTB_VERSION:-5.0}/bin:\$PATH bash ${test_script}" "${SVC_USER}"; then
        log "${test_name}: PASSED"
        TOTAL_PASS=$((TOTAL_PASS + 1))
    else
        log "${test_name}: FAILED"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
done

# Cleanup
log "Stopping cluster..."
stop_services
rm -rf "${TEST_BASE}"
[ "${SVC_USER}" = "otbtest" ] && userdel otbtest 2>/dev/null || true

# Summary
echo ""
log "========================================="
log "  Advanced Tests: ${TOTAL_PASS} passed, ${TOTAL_FAIL} failed"
log "========================================="

if [ "${TOTAL_FAIL}" -gt 0 ]; then
    exit 1
fi
exit 0
