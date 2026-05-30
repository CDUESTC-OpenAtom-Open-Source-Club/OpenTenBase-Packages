#!/usr/bin/env bash
# OpenTenBase Advanced Test: Transactions
# Tests distributed transaction commit/rollback, cross-node consistency,
# isolation levels, and savepoints.
set -euo pipefail

COORD_HOST="127.0.0.1"
COORD_PORT="5432"
PSQL="psql -h ${COORD_HOST} -p ${COORD_PORT} -XAt"

PASS_COUNT=0
FAIL_COUNT=0

log_pass() { echo -e "[32m[PASS][0m $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
log_fail() { echo -e "[31m[FAIL][0m $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
log_info() { echo -e "[36m[INFO][0m $1"; }

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
log_info "Checking if Coordinator is reachable on ${COORD_HOST}:${COORD_PORT}..."
if ! pg_isready -h "${COORD_HOST}" -p "${COORD_PORT}" -q; then
    log_fail "Coordinator is not running on ${COORD_HOST}:${COORD_PORT}"
    exit 1
fi
log_info "Coordinator is up."

# ---------------------------------------------------------------------------
# Cleanup helper
# ---------------------------------------------------------------------------
cleanup() {
    log_info "Cleaning up test tables..."
    ${PSQL} -c "DROP TABLE IF EXISTS txn_test CASCADE;" postgres 2>/dev/null || true
    ${PSQL} -c "DROP TABLE IF EXISTS txn_test_a CASCADE;" postgres 2>/dev/null || true
    ${PSQL} -c "DROP TABLE IF EXISTS txn_test_b CASCADE;" postgres 2>/dev/null || true
}
trap cleanup EXIT
cleanup

# ===========================================================================
# Test 1: Basic COMMIT
# ===========================================================================
log_info "Test 1: Basic distributed COMMIT"
${PSQL} -c "CREATE TABLE txn_test (id int PRIMARY KEY, val text) distribute by shard(id);" postgres
${PSQL} -c "BEGIN; INSERT INTO txn_test VALUES (1, 'hello'); COMMIT;" postgres
result=$(${PSQL} -c "SELECT val FROM txn_test WHERE id = 1;" postgres)
if [[ "$result" == "hello" ]]; then
    log_pass "Basic COMMIT -- value persisted correctly"
else
    log_fail "Basic COMMIT -- expected 'hello', got '${result}'"
fi

# ===========================================================================
# Test 2: ROLLBACK
# ===========================================================================
log_info "Test 2: Distributed ROLLBACK"
${PSQL} -c "BEGIN; INSERT INTO txn_test VALUES (2, 'rollback_me'); ROLLBACK;" postgres
count=$(${PSQL} -c "SELECT count(*) FROM txn_test WHERE id = 2;" postgres)
if [[ "$count" == "0" ]]; then
    log_pass "ROLLBACK -- row correctly not persisted"
else
    log_fail "ROLLBACK -- row should not exist but count=${count}"
fi

# ===========================================================================
# Test 3: Cross-node consistency
# ===========================================================================
log_info "Test 3: Cross-node transaction consistency"
${PSQL} -c "CREATE TABLE txn_test_a (id int PRIMARY KEY, ref_id int) distribute by shard(id);" postgres
${PSQL} -c "CREATE TABLE txn_test_b (id int PRIMARY KEY, data text) distribute by shard(id);" postgres

${PSQL} -c "
BEGIN;
INSERT INTO txn_test_b VALUES (100, 'cross_node');
INSERT INTO txn_test_a VALUES (1, 100);
COMMIT;
" postgres

a_ref=$(${PSQL} -c "SELECT ref_id FROM txn_test_a WHERE id = 1;" postgres)
b_data=$(${PSQL} -c "SELECT data FROM txn_test_b WHERE id = 100;" postgres)
if [[ "$a_ref" == "100" && "$b_data" == "cross_node" ]]; then
    log_pass "Cross-node consistency -- both tables updated atomically"
else
    log_fail "Cross-node consistency -- a_ref=${a_ref}, b_data=${b_data}"
fi

# ===========================================================================
# Test 4: Transaction isolation -- READ COMMITTED
# ===========================================================================
log_info "Test 4: READ COMMITTED isolation"
${PSQL} -c "TRUNCATE txn_test;" postgres
${PSQL} -c "INSERT INTO txn_test VALUES (10, 'original');" postgres

# Start a transaction, update but don't commit yet is hard in single psql,
# so we verify READ COMMITTED behaviour by checking that non-locked rows are visible.
val=$(${PSQL} -c "BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED; SELECT val FROM txn_test WHERE id = 10; COMMIT;" postgres)
if [[ "$val" == "original" ]]; then
    log_pass "READ COMMITTED -- can read committed data"
else
    log_fail "READ COMMITTED -- expected 'original', got '${val}'"
fi

# ===========================================================================
# Test 5: SAVEPOINT and partial rollback
# ===========================================================================
log_info "Test 5: SAVEPOINT / ROLLBACK TO SAVEPOINT"
${PSQL} -c "TRUNCATE txn_test;" postgres
${PSQL} -c "
BEGIN;
INSERT INTO txn_test VALUES (1, 'before_sp');
SAVEPOINT sp1;
INSERT INTO txn_test VALUES (2, 'in_sp');
ROLLBACK TO SAVEPOINT sp1;
INSERT INTO txn_test VALUES (3, 'after_sp');
COMMIT;
" postgres

count_total=$(${PSQL} -c "SELECT count(*) FROM txn_test;" postgres)
has_2=$(${PSQL} -c "SELECT count(*) FROM txn_test WHERE id = 2;" postgres)
has_1=$(${PSQL} -c "SELECT count(*) FROM txn_test WHERE id = 1;" postgres)
has_3=$(${PSQL} -c "SELECT count(*) FROM txn_test WHERE id = 3;" postgres)

if [[ "$has_1" == "1" && "$has_2" == "0" && "$has_3" == "1" && "$count_total" == "2" ]]; then
    log_pass "SAVEPOINT -- partial rollback works correctly (rows: ${count_total})"
else
    log_fail "SAVEPOINT -- unexpected state (total=${count_total}, id1=${has_1}, id2=${has_2}, id3=${has_3})"
fi

# ===========================================================================
# Test 6: Nested SAVEPOINT
# ===========================================================================
log_info "Test 6: Nested SAVEPOINT"
${PSQL} -c "TRUNCATE txn_test;" postgres
${PSQL} -c "
BEGIN;
INSERT INTO txn_test VALUES (1, 'outer');
SAVEPOINT outer_sp;
INSERT INTO txn_test VALUES (2, 'inner');
SAVEPOINT inner_sp;
INSERT INTO txn_test VALUES (3, 'deep');
ROLLBACK TO SAVEPOINT inner_sp;
COMMIT;
" postgres

count_total=$(${PSQL} -c "SELECT count(*) FROM txn_test;" postgres)
if [[ "$count_total" == "2" ]]; then
    log_pass "Nested SAVEPOINT -- correct row count after nested rollback (${count_total})"
else
    log_fail "Nested SAVEPOINT -- expected 2 rows, got ${count_total}"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
log_info "========================================="
log_info "  Transaction Tests: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
log_info "========================================="

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
    exit 1
fi
exit 0
