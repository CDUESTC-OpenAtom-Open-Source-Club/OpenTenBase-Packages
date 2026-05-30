#!/bin/bash
# OpenTenBase Docker entrypoint
# If running as root: fix volume permissions, then re-exec as opentenbase
# If running as opentenbase: initialize and start the node

set -e

NODE_TYPE="${NODE_TYPE:-}"
NODE_NAME="${NODE_NAME:-}"
GTM_HOST="${GTM_HOST:-gtm}"
GTM_PORT="${GTM_PORT:-6666}"
COORD_HOST="${COORD_HOST:-coordinator}"
COORD_PORT="${COORD_PORT:-5432}"
DN_PORT="${DN_PORT:-15432}"
DN_FORWARD_PORT="${DN_FORWARD_PORT:-6670}"

DATA_DIR="/var/lib/opentenbase/data/${NODE_NAME}"

log() {
    echo "[${NODE_NAME}] $(date '+%H:%M:%S') $1"
}

wait_for_port() {
    local host=$1 port=$2 timeout=${3:-60}
    log "Waiting for ${host}:${port}..."
    for i in $(seq 1 "$timeout"); do
        # Try bash /dev/tcp first
        if bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null; then
            log "${host}:${port} is ready"
            return 0
        fi
        # Fallback: try nc (netcat) if available
        if command -v nc &>/dev/null && nc -z -w1 "$host" "$port" 2>/dev/null; then
            log "${host}:${port} is ready (via nc)"
            return 0
        fi
        sleep 1
    done
    log "ERROR: ${host}:${port} not ready after ${timeout}s"
    return 1
}

query_coordinator() {
    /usr/lib/opentenbase/5.0/bin/psql -h "$COORD_HOST" -p "$COORD_PORT" -U opentenbase -d postgres -t -A -c "$1" 2>/dev/null || true
}

# Resolve hostname to IPv4 (required for forward manager hostname verification)
# Prefer IPv4 — getent may return ::1 (IPv6 loopback) for local hostnames
resolve_ip() {
    local result
    result=$(getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | head -1)
    if [ -z "$result" ]; then
        result=$(getent hosts "$1" 2>/dev/null | awk '{print $1}' | grep -v '^::' | head -1)
    fi
    echo "${result:-$1}"
}

# ============================================
# If root, fix permissions and re-exec as opentenbase
# ============================================
if [ "$(id -u)" -eq 0 ]; then
    mkdir -p "$DATA_DIR" /var/lib/opentenbase/data
    chown -R opentenbase:opentenbase /var/lib/opentenbase
    exec runuser -u opentenbase -- /bin/bash "$0" "$@"
fi

# ============================================
# Below runs as opentenbase user
# ============================================

# Resolve all hostnames to IPs at startup
GTM_IP=$(resolve_ip "$GTM_HOST")
COORD_IP=$(resolve_ip "$COORD_HOST")
MY_IP=$(resolve_ip "$(hostname)")

log "Resolved IPs: gtm=$GTM_IP, coordinator=$COORD_IP, self=$MY_IP"

case "$NODE_TYPE" in
# --- GTM ---
gtm)
    if [ ! -f "$DATA_DIR/gtm.conf" ]; then
        log "Initializing GTM..."
        /usr/lib/opentenbase/5.0/bin/initgtm -Z gtm -D "$DATA_DIR"
        cat >> "$DATA_DIR/gtm.conf" <<EOF
port = $GTM_PORT
listen_addresses = '*'
EOF
    fi
    log "Starting GTM on port $GTM_PORT..."
    exec /usr/lib/opentenbase/5.0/bin/gtm -D "$DATA_DIR" -l /var/lib/opentenbase/data/gtm.log
    ;;

# --- Coordinator ---
coordinator)
    if [ ! -f "$DATA_DIR/postgresql.conf" ]; then
        log "Initializing Coordinator..."
        /usr/lib/opentenbase/5.0/bin/initdb -D "$DATA_DIR" --nodename=coordinator --nodetype=coordinator \
            --master_gtm_nodename=gtm_master --master_gtm_ip="$GTM_HOST" --master_gtm_port="$GTM_PORT"
        cat >> "$DATA_DIR/postgresql.conf" <<EOF
port = $COORD_PORT
listen_addresses = '*'
pooler_port = 6669
forward_port = 6670
EOF
        echo "host all all 0.0.0.0/0 md5" >> "$DATA_DIR/pg_hba.conf"
    fi

    wait_for_port "$GTM_IP" "$GTM_PORT"

    log "Starting Coordinator on port $COORD_PORT..."
    /usr/lib/opentenbase/5.0/bin/postgres --coordinator -D "$DATA_DIR" &
    COORD_PID=$!

    wait_for_port "127.0.0.1" "$COORD_PORT" 30

    log "Registering nodes in pgxc_node..."
    /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE gtm_master WITH (TYPE='gtm', HOST='$GTM_IP', PORT=$GTM_PORT);" 2>/dev/null || true
    /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE datanode1 WITH (TYPE='datanode', HOST='datanode1', PORT=15432, FORWARD=$DN_FORWARD_PORT);" 2>/dev/null || true
    /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE datanode2 WITH (TYPE='datanode', HOST='datanode2', PORT=15433, FORWARD=$DN_FORWARD_PORT);" 2>/dev/null || true

    # Resolve datanode hostnames to IPs for forward manager compatibility
    DN1_IP=$(resolve_ip "datanode1")
    DN2_IP=$(resolve_ip "datanode2")
    log "Resolved datanode IPs: dn1=$DN1_IP, dn2=$DN2_IP"

    # Update datanodes with resolved IPs
    /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "ALTER NODE datanode1 WITH (HOST='$DN1_IP', PORT=15432, FORWARD=$DN_FORWARD_PORT);" 2>/dev/null || true
    /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "ALTER NODE datanode2 WITH (HOST='$DN2_IP', PORT=15433, FORWARD=$DN_FORWARD_PORT);" 2>/dev/null || true
    # Update coordinator's own entry to include forward port
    /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "ALTER NODE coordinator WITH (HOST='$COORD_IP', PORT=$COORD_PORT, FORWARD=6670);" 2>/dev/null || true
    /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "SELECT pgxc_pool_reload();" 2>/dev/null || true

    log "Coordinator ready"
    wait $COORD_PID
    ;;

# --- Datanode ---
datanode)
    if [ ! -f "$DATA_DIR/postgresql.conf" ]; then
        log "Initializing Datanode..."
        /usr/lib/opentenbase/5.0/bin/initdb -D "$DATA_DIR" --nodename="$NODE_NAME" --nodetype=datanode \
            --master_gtm_nodename=gtm_master --master_gtm_ip="$GTM_HOST" --master_gtm_port="$GTM_PORT"
        cat >> "$DATA_DIR/postgresql.conf" <<EOF
port = $DN_PORT
listen_addresses = '*'
pooler_port = 6669
forward_port = $DN_FORWARD_PORT
EOF
        echo "host all all 0.0.0.0/0 md5" >> "$DATA_DIR/pg_hba.conf"
    fi

    wait_for_port "$GTM_IP" "$GTM_PORT"
    wait_for_port "$COORD_IP" "$COORD_PORT"

    log "Starting Datanode on port $DN_PORT..."
    /usr/lib/opentenbase/5.0/bin/postgres --datanode -D "$DATA_DIR" &
    DN_PID=$!

    wait_for_port "127.0.0.1" "$DN_PORT" 30

    # Read correct node_ids from coordinator
    log "Synchronizing node_ids with coordinator..."
    COORD_NODE_ID=""
    MY_NODE_ID=""
    for i in $(seq 1 30); do
        COORD_NODE_ID=$(query_coordinator "SELECT node_id FROM pgxc_node WHERE node_name='coordinator';")
        MY_NODE_ID=$(query_coordinator "SELECT node_id FROM pgxc_node WHERE node_name='$NODE_NAME';")
        if [ -n "$COORD_NODE_ID" ] && [ -n "$MY_NODE_ID" ]; then
            break
        fi
        log "Waiting for coordinator to register nodes (attempt $i/30)..."
        sleep 2
    done

    if [ -z "$COORD_NODE_ID" ] || [ -z "$MY_NODE_ID" ]; then
        log "ERROR: Could not read node_ids from coordinator (coord=$COORD_NODE_ID, mine=$MY_NODE_ID)"
        exit 1
    fi

    log "Coordinator node_id=$COORD_NODE_ID, my node_id=$MY_NODE_ID"

    # Get peer datanode info
    OTHER_DN_NAME=""
    OTHER_DN_PORT=""
    if [ "$NODE_NAME" = "datanode1" ]; then
        OTHER_DN_NAME="datanode2"
        OTHER_DN_PORT=15433
    elif [ "$NODE_NAME" = "datanode2" ]; then
        OTHER_DN_NAME="datanode1"
        OTHER_DN_PORT=15432
    fi
    OTHER_DN_NODE_ID=$(query_coordinator "SELECT node_id FROM pgxc_node WHERE node_name='$OTHER_DN_NAME';")
    OTHER_DN_IP=$(resolve_ip "$OTHER_DN_NAME")

    # Fix pgxc_node on this datanode using allow_dml_on_datanode to bypass read-only
    log "Applying pgxc_node synchronization..."
    SQL_FILE="/tmp/fix_node_ids.sql"
    cat > "$SQL_FILE" <<EOSQL
SET allow_dml_on_datanode = true;
-- Update self-node with correct port and forward_port
UPDATE pgxc_node SET node_id=$MY_NODE_ID, node_host='$MY_IP', node_port=$DN_PORT, node_forward_port=$DN_FORWARD_PORT, nodeis_preferred=true WHERE node_type='D' AND node_name='$NODE_NAME';
-- Delete and re-insert coordinator and peer datanode entries with correct node_ids
DELETE FROM pgxc_node WHERE node_name='coordinator' OR node_name='$OTHER_DN_NAME';
INSERT INTO pgxc_node (node_name, node_type, node_id, node_host, node_port, node_forward_port, nodeis_primary, nodeis_preferred, node_plane_name, node_plane_id) VALUES ('coordinator', 'C', $COORD_NODE_ID, '$COORD_IP', $COORD_PORT, 6670, false, false, 'opentenbase_cluster', 0);
INSERT INTO pgxc_node (node_name, node_type, node_id, node_host, node_port, node_forward_port, nodeis_primary, nodeis_preferred, node_plane_name, node_plane_id) VALUES ('$OTHER_DN_NAME', 'D', $OTHER_DN_NODE_ID, '$OTHER_DN_IP', $OTHER_DN_PORT, $DN_FORWARD_PORT, false, true, 'opentenbase_cluster', 0);
EOSQL

    /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$DN_PORT" -U opentenbase -d postgres -f "$SQL_FILE" 2>&1 || true
    rm -f "$SQL_FILE"
    /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$DN_PORT" -U opentenbase -d postgres -c \
        "SELECT pgxc_pool_reload();" 2>/dev/null || true

    # Verify node configuration
    log "Final node verification:"
    /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$DN_PORT" -U opentenbase -d postgres -c \
        "SELECT node_name, node_type, node_id, node_host, node_port, node_forward_port FROM pgxc_node ORDER BY node_name;"

    # If this is datanode1, create node group on coordinator after all datanodes are ready
    if [ "$NODE_NAME" = "datanode1" ]; then
        log "Waiting for all datanodes to be registered on coordinator..."
        for i in $(seq 1 30); do
            DN_COUNT=$(query_coordinator "SELECT count(*) FROM pgxc_node WHERE node_type='D';")
            if [ "$DN_COUNT" = "2" ]; then
                log "Both datanodes registered on coordinator"
                break
            fi
            log "Waiting for datanodes (found $DN_COUNT/2, attempt $i/30)..."
            sleep 2
        done

        # Add delay to ensure coordinator has fully processed the registrations
        sleep 3

        log "Creating node group on coordinator..."
        for i in $(seq 1 5); do
            RESULT=$(/usr/lib/opentenbase/5.0/bin/psql -h "$COORD_HOST" -p "$COORD_PORT" -U opentenbase -d postgres -t -A -c \
                "CREATE DEFAULT NODE GROUP default_group WITH (datanode1, datanode2);" 2>&1)
            if echo "$RESULT" | grep -q "CREATE NODE GROUP"; then
                log "Node group created successfully"
                break
            fi
            log "Node group creation attempt $i failed: $RESULT"
            sleep 2
        done
        /usr/lib/opentenbase/5.0/bin/psql -h "$COORD_HOST" -p "$COORD_PORT" -U opentenbase -d postgres -c \
            "SELECT pgxc_pool_reload();" 2>/dev/null || true

        # Add delay before creating sharding group
        sleep 2

        log "Initializing shard map..."
        for i in $(seq 1 5); do
            RESULT=$(/usr/lib/opentenbase/5.0/bin/psql -h "$COORD_HOST" -p "$COORD_PORT" -U opentenbase -d postgres -t -A -c \
                "CREATE SHARDING GROUP TO GROUP default_group;" 2>&1)
            if echo "$RESULT" | grep -q "CREATE SHARDING GROUP"; then
                log "Shard map created successfully"
                break
            fi
            log "Shard map creation attempt $i failed: $RESULT"
            sleep 2
        done
        log "Node group and shard map created"
    fi

    log "Datanode ready"
    wait $DN_PID
    ;;

*)
    log "ERROR: NODE_TYPE must be gtm, coordinator, or datanode"
    exit 1
    ;;
esac
