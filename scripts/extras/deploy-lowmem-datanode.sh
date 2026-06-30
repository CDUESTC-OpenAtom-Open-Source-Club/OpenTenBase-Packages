#!/bin/bash
# OpenTenBase 低内存部署脚本 (适用于 1-2GB RAM 服务器)
# 仅部署 Datanode，连接远程 GTM 和 Coordinator
#
# Usage: ./deploy-lowmem-datanode.sh --gtm-ip <IP> --gtm-port 6666 --dn-name dn1 --dn-port 15432

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Default values
GTM_IP=""
GTM_PORT="6666"
DN_NAME="dn1"
DN_PORT="15432"
DN_POOLER_PORT="6668"
OTB_VERSION="5.0"
OTB_USER="opentenbase"
DATA_DIR="/var/lib/opentenbase/${OTB_VERSION}/${DN_NAME}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --gtm-ip) GTM_IP="$2"; shift 2 ;;
        --gtm-port) GTM_PORT="$2"; shift 2 ;;
        --dn-name) DN_NAME="$2"; shift 2 ;;
        --dn-port) DN_PORT="$2"; shift 2 ;;
        --version) OTB_VERSION="$2"; shift 2 ;;
        --help)
            echo "Usage: $0 --gtm-ip <IP> [--gtm-port 6666] [--dn-name dn1] [--dn-port 15432]"
            echo ""
            echo "Options:"
            echo "  --gtm-ip      GTM server IP address (required)"
            echo "  --gtm-port    GTM port (default: 6666)"
            echo "  --dn-name     Datanode name (default: dn1)"
            echo "  --dn-port     Datanode port (default: 15432)"
            echo "  --version     OpenTenBase version (default: 5.0)"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1 ;;
    esac
done

# Check required arguments
if [ -z "$GTM_IP" ]; then
    log_error "--gtm-ip is required"
    exit 1
fi

# Check memory
AVAIL_RAM_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
log_info "Detected ${AVAIL_RAM_MB}MB RAM"

if [ "$AVAIL_RAM_MB" -lt 1000 ]; then
    log_error "Memory too low (<1GB). Cannot run OpenTenBase."
    exit 1
fi

if [ "$AVAIL_RAM_MB" -lt 2000 ]; then
    log_warn "Memory is low (<2GB). Using minimal configuration."
fi

# Check if OpenTenBase is installed
OTB_HOME="/usr/lib/opentenbase/${OTB_VERSION}"
if [ ! -d "$OTB_HOME" ]; then
    log_error "OpenTenBase ${OTB_VERSION} not installed at ${OTB_HOME}"
    log_info "Install with: curl -sSL https://raw.githubusercontent.com/.../setup-rpm.sh | sudo bash"
    exit 1
fi

OTB_BIN="$OTB_HOME/bin"
if [ ! -x "$OTB_BIN/initdb" ]; then
    log_error "initdb not found at $OTB_BIN"
    exit 1
fi

# Check/create swap if needed
if [ "$AVAIL_RAM_MB" -lt 2000 ]; then
    SWAP_TOTAL=$(awk '/SwapTotal/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo "0")
    if [ "$SWAP_TOTAL" -lt 512 ]; then
        log_warn "Swap is small (${SWAP_TOTAL}MB). Creating 1GB swap..."
        if [ -f /swapfile-opentenbase ]; then
            log_info "Swap file already exists"
        else
            sudo fallocate -l 1G /swapfile-opentenbase || {
                log_warn "fallocate failed, using dd..."
                sudo dd if=/dev/zero of=/swapfile-opentenbase bs=1M count=1024 status=progress
            }
            sudo chmod 600 /swapfile-opentenbase
            sudo mkswap /swapfile-opentenbase
            sudo swapon /swapfile-opentenbase
            log_info "Swap created and enabled"
        fi
    fi
fi

# Create user if needed
if ! id "$OTB_USER" &>/dev/null; then
    log_info "Creating user $OTB_USER..."
    useradd --system --home-dir /var/lib/opentenbase --shell /bin/bash "$OTB_USER"
fi

# Create data directory
log_info "Creating data directory: $DATA_DIR"
install -d -o "$OTB_USER" -g "$OTB_USER" -m 0700 "$DATA_DIR"

# Initialize Datanode
log_info "Initializing Datanode $DN_NAME..."
su - "$OTB_USER" -c "$OTB_BIN/initdb -D '$DATA_DIR' \
    --nodename='$DN_NAME' --nodetype=datanode \
    --master_gtm_nodename=gtm_master \
    --master_gtm_ip='$GTM_IP' \
    --master_gtm_port='$GTM_PORT' \
    --locale=C.UTF-8 -E UTF8 -U '$OTB_USER'"

# Apply low-memory configuration
log_info "Applying low-memory configuration..."
cat >> "$DATA_DIR/postgresql.conf" << EOF

# --- Low-memory configuration (detected ${AVAIL_RAM_MB}MB RAM) ---
listen_addresses = '*'
port = $DN_PORT
pooler_port = $DN_POOLER_PORT
pgxc_node_name = '$DN_NAME'

# Minimal connections
max_connections = 20
superuser_reserved_connections = 3

# Minimal shared buffers (must be physical RAM)
shared_buffers = 16MB
dynamic_shared_memory_type = posix

# Minimal pool size
max_pool_size = 20

# Minimal work memory
work_mem = 4MB
maintenance_work_mem = 64MB
autovacuum_work_mem = 16MB

# Minimal WAL
wal_buffers = 4MB

# Cache size estimate
effective_cache_size = 256MB

# Background writer - more frequent to reduce pressure
bgwriter_delay = 200ms
bgwriter_lru_maxpages = 100

# Logging
logging_collector = on
log_directory = '/var/log/opentenbase/${OTB_VERSION}'
log_filename = '${DN_NAME}.log'
log_min_duration_statement = 1000
EOF

log_info "Configuration applied"

# Start Datanode
log_info "Starting Datanode..."
su - "$OTB_USER" -c "$OTB_BIN/pg_ctl -D '$DATA_DIR' -l /var/log/opentenbase/${OTB_VERSION}/${DN_NAME}.log start"

# Check if started
sleep 3
if su - "$OTB_USER" -c "$OTB_BIN/pg_ctl -D '$DATA_DIR' status" | grep -q "server is running"; then
    log_info "Datanode $DN_NAME started successfully on port $DN_PORT"
else
    log_error "Datanode failed to start. Check logs:"
    log_error "  tail -50 /var/log/opentenbase/${OTB_VERSION}/${DN_NAME}.log"
    exit 1
fi

# Summary
echo ""
echo "========================================"
echo "  Datanode $DN_NAME deployed successfully"
echo "========================================"
echo ""
echo "Memory usage estimate: ~400-600MB"
echo ""
echo "Next steps:"
echo "1. On Coordinator, register this Datanode:"
echo "   CREATE NODE $DN_NAME WITH (TYPE='datanode', HOST='<THIS_SERVER_IP>', PORT=$DN_PORT, PRIMARY, PREFERRED);"
echo "   SELECT pgxc_pool_reload();"
echo ""
echo "2. Add to default group:"
echo "   CREATE NODE GROUP default_group WITH ($DN_NAME);"
echo ""
echo "Logs: /var/log/opentenbase/${OTB_VERSION}/${DN_NAME}.log"
echo ""