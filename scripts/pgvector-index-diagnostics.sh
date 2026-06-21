#!/usr/bin/env bash
set -euo pipefail

DBNAME="${DBNAME:-postgres}"
ROW_COUNT="${ROW_COUNT:-100000}"
DIMS="${DIMS:-128}"
LISTS="${LISTS:-}"
PROBES="${PROBES:-}"
TARGET_RECALL="${TARGET_RECALL:-0.90}"
MAINTENANCE_WORK_MEM="${MAINTENANCE_WORK_MEM:-}"
SQL_FILE="${SQL_FILE:-}"

usage() {
    cat <<USAGE
Usage:
  DBNAME=postgres ROW_COUNT=100000 DIMS=128 LISTS=1000 PROBES=500 \\
    TARGET_RECALL=0.90 MAINTENANCE_WORK_MEM=512MB \\
    SQL_FILE=/path/to/ivfflat_diagnostics.sql \\
    $0

Environment:
  DBNAME                 target database, default: postgres
  ROW_COUNT              vector row count, default: 100000
  DIMS                   vector dimensions, default: 128
  LISTS                  IVFFlat lists; empty means use recommendation heuristic
  PROBES                 IVFFlat probes; empty means use target recall heuristic
  TARGET_RECALL          expected recall target, default: 0.90
  MAINTENANCE_WORK_MEM   memory setting to diagnose; empty means current DB setting
  SQL_FILE               optional ivfflat_diagnostics.sql path to load before running

Connection variables such as PGHOST, PGPORT, PGUSER and PGPASSWORD are passed
through to psql.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

psql_cmd() {
    psql -X -v ON_ERROR_STOP=1 -d "$DBNAME" "$@"
}

sql_literal_or_null() {
    local value="$1"
    if [[ -z "$value" ]]; then
        printf 'NULL'
    else
        printf "'%s'" "${value//\'/\'\'}"
    fi
}

int_or_null() {
    local value="$1"
    if [[ -z "$value" ]]; then
        printf 'NULL'
    else
        printf '%s' "$value"
    fi
}

if [[ -n "$SQL_FILE" ]]; then
    psql_cmd -f "$SQL_FILE"
fi

lists_sql="$(int_or_null "$LISTS")"
probes_sql="$(int_or_null "$PROBES")"
mem_sql="$(sql_literal_or_null "$MAINTENANCE_WORK_MEM")"

psql_cmd -c "
SELECT check_name, status, detail, recommendation
FROM pgvector_bench.diagnose_ivfflat_build(
    ${ROW_COUNT},
    ${DIMS},
    ${lists_sql},
    ${probes_sql},
    ${TARGET_RECALL},
    ${mem_sql}
);
"

psql_cmd -c "
SELECT schema_name, table_name, index_name, pg_size_pretty(index_bytes) AS index_size, index_kind
FROM pgvector_bench.ivfflat_index_inventory
ORDER BY index_bytes DESC
LIMIT 20;
"

