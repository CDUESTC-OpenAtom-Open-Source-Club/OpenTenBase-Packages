#!/bin/bash
# OpenTenBase Docker Compose 一键部署测试脚本
# 用法: bash test-docker.sh

set -e

echo "=========================================="
echo "OpenTenBase Docker Compose 部署测试"
echo "=========================================="

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker 未安装"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "ERROR: Docker daemon 未运行"
    exit 1
fi

echo "[1/5] 创建目录结构..."
mkdir -p /tmp/otb-docker/runtime /tmp/otb-docker/compose

echo "[2/5] 下载 .deb 包..."
cd /tmp/otb-docker/runtime
for deb in \
    opentenbase_5.0-1ubuntu1.noble_all.deb \
    opentenbase-server_5.0-1ubuntu1.noble_amd64.deb \
    opentenbase-client_5.0-1ubuntu1.noble_amd64.deb \
    opentenbase-contrib_5.0-1ubuntu1.noble_amd64.deb; do
    if [ ! -f "$deb" ]; then
        echo "  下载 $deb..."
        curl -sL -o "$deb" "https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi10/$deb"
    fi
done
ls -la *.deb

echo "[3/5] 创建 Dockerfile..."
cat > /tmp/otb-docker/runtime/Dockerfile.runtime << 'DOCKERFILE'
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libreadline8 \
    libssl3 \
    libxml2 \
    libcurl4 \
    libpam0g \
    liblz4-1 \
    libzstd1 \
    libssh2-1 \
    libuuid1 \
    libatomic1 \
    adduser \
    sudo \
    curl \
    iputils-ping \
    net-tools \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Install OpenTenBase packages
COPY *.deb /tmp/debs/
RUN dpkg -i --force-depends /tmp/debs/*.deb \
    && rm -rf /tmp/debs

# Create opentenbase user
RUN useradd -m -s /bin/bash opentenbase || true

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
DOCKERFILE

echo "[4/5] 创建 entrypoint.sh..."
cat > /tmp/otb-docker/runtime/entrypoint.sh << 'ENTRYPOINT'
#!/bin/bash
set -e

NODE_TYPE="${NODE_TYPE:-}"
NODE_NAME="${NODE_NAME:-}"
GTM_HOST="${GTM_HOST:-gtm}"
GTM_PORT="${GTM_PORT:-6666}"
COORD_HOST="${COORD_HOST:-coordinator}"
COORD_PORT="${COORD_PORT:-5432}"
DN_PORT="${DN_PORT:-15432}"

DATA_DIR="/var/lib/opentenbase/data/${NODE_NAME}"

log() {
    echo "[${NODE_NAME}] $(date '+%H:%M:%S') $1"
}

resolve_ip() {
    getent hosts "$1" 2>/dev/null | awk '{print $1}' || echo "$1"
}

wait_for_port() {
    local host=$1 port=$2 timeout=${3:-60}
    log "Waiting for ${host}:${port}..."
    for i in $(seq 1 "$timeout"); do
        if bash -c "echo > /dev/tcp/${host}/${port}" 2>/dev/null; then
            log "${host}:${port} is ready"
            return 0
        fi
        if command -v nc &>/dev/null && nc -z -w1 "$host" "$port" 2>/dev/null; then
            log "${host}:${port} is ready (via nc)"
            return 0
        fi
        sleep 1
    done
    log "ERROR: ${host}:${port} not ready after ${timeout}s"
    return 1
}

init_gtm() {
    if [ ! -f "$DATA_DIR/gtm.conf" ]; then
        log "Initializing GTM..."
        mkdir -p "$DATA_DIR"
        chown opentenbase:opentenbase "$DATA_DIR"
        sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/initgtm -Z gtm -D "$DATA_DIR"
        cat >> "$DATA_DIR/gtm.conf" <<EOF
port = $GTM_PORT
listen_addresses = '*'
EOF
    fi
    log "Starting GTM on port $GTM_PORT..."
    exec sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/gtm -D "$DATA_DIR"
}

init_coordinator() {
    if [ ! -f "$DATA_DIR/postgresql.conf" ]; then
        log "Initializing Coordinator..."
        mkdir -p "$DATA_DIR"
        chown opentenbase:opentenbase "$DATA_DIR"
        sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/initdb -D "$DATA_DIR" --nodename=coordinator --nodetype=coordinator
        cat >> "$DATA_DIR/postgresql.conf" <<EOF
port = $COORD_PORT
listen_addresses = '*'
gtm_host = '$GTM_HOST'
gtm_port = $GTM_PORT
pooler_port = $((COORD_PORT + 2000))
EOF
        echo "host all all 0.0.0.0/0 trust" >> "$DATA_DIR/pg_hba.conf"
    fi

    GTM_IP=$(resolve_ip "$GTM_HOST")
    wait_for_port "$GTM_IP" "$GTM_PORT"

    log "Starting Coordinator on port $COORD_PORT..."
    sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/postgres --coordinator -D "$DATA_DIR" &
    COORD_PID=$!

    wait_for_port "127.0.0.1" "$COORD_PORT" 30

    COORD_IP=$(resolve_ip "$COORD_HOST")
    DN1_IP=$(resolve_ip "datanode1")
    DN2_IP=$(resolve_ip "datanode2")
    log "Resolved IPs: gtm=$GTM_IP, coord=$COORD_IP, dn1=$DN1_IP, dn2=$DN2_IP"

    log "Registering nodes..."
    sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE gtm_master WITH (TYPE='gtm', HOST='$GTM_IP', PORT=$GTM_PORT);" 2>/dev/null || true
    sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE coord1 WITH (TYPE='coordinator', HOST='$COORD_IP', PORT=$COORD_PORT, PREFERRED);" 2>/dev/null || true
    sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE dn001 WITH (TYPE='datanode', HOST='$DN1_IP', PORT=15432, PREFERRED);" 2>/dev/null || true
    sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE dn002 WITH (TYPE='datanode', HOST='$DN2_IP', PORT=15433);" 2>/dev/null || true
    sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$COORD_PORT" -U opentenbase -d postgres -c \
        "SELECT pgxc_pool_reload();" 2>/dev/null || true

    log "Coordinator ready"
    wait $COORD_PID
}

init_datanode() {
    if [ ! -f "$DATA_DIR/postgresql.conf" ]; then
        log "Initializing Datanode..."
        mkdir -p "$DATA_DIR"
        chown opentenbase:opentenbase "$DATA_DIR"
        sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/initdb -D "$DATA_DIR" --nodename="$NODE_NAME" --nodetype=datanode
        cat >> "$DATA_DIR/postgresql.conf" <<EOF
port = $DN_PORT
listen_addresses = '*'
gtm_host = '$GTM_HOST'
gtm_port = $GTM_PORT
pooler_port = $((DN_PORT + 2000))
EOF
        echo "host all all 0.0.0.0/0 trust" >> "$DATA_DIR/pg_hba.conf"
    fi

    GTM_IP=$(resolve_ip "$GTM_HOST")
    COORD_IP=$(resolve_ip "$COORD_HOST")
    MY_IP=$(resolve_ip "$(hostname)")
    wait_for_port "$GTM_IP" "$GTM_PORT"

    log "Starting Datanode on port $DN_PORT..."
    sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/postgres --datanode -D "$DATA_DIR" &
    DN_PID=$!

    wait_for_port "127.0.0.1" "$DN_PORT" 30

    log "Registering nodes on datanode..."
    sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$DN_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE gtm_master WITH (TYPE='gtm', HOST='$GTM_IP', PORT=$GTM_PORT);" 2>/dev/null || true
    sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$DN_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE coord1 WITH (TYPE='coordinator', HOST='$COORD_IP', PORT=$COORD_PORT);" 2>/dev/null || true
    sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$DN_PORT" -U opentenbase -d postgres -c \
        "CREATE NODE $NODE_NAME WITH (TYPE='datanode', HOST='$MY_IP', PORT=$DN_PORT, PREFERRED);" 2>/dev/null || true
    sudo -u opentenbase /usr/lib/opentenbase/5.0/bin/psql -h 127.0.0.1 -p "$DN_PORT" -U opentenbase -d postgres -c \
        "SELECT pgxc_pool_reload();" 2>/dev/null || true

    log "Datanode ready"
    wait $DN_PID
}

case "$NODE_TYPE" in
    gtm)         init_gtm ;;
    coordinator) init_coordinator ;;
    datanode)    init_datanode ;;
    *)
        log "ERROR: NODE_TYPE must be gtm, coordinator, or datanode"
        exit 1
        ;;
esac
ENTRYPOINT
chmod +x /tmp/otb-docker/runtime/entrypoint.sh

echo "[5/5] 创建 docker-compose.yml..."
cat > /tmp/otb-docker/compose/docker-compose.yml << 'COMPOSE'
services:
  gtm:
    build:
      context: ../runtime
      dockerfile: Dockerfile.runtime
    image: opentenbase-runtime:latest
    container_name: opentenbase-gtm
    hostname: gtm
    environment:
      - NODE_TYPE=gtm
      - NODE_NAME=gtm
      - GTM_PORT=6666
    ports:
      - "6666:6666"
    volumes:
      - gtm_data:/var/lib/opentenbase/data/gtm
    networks:
      - opentenbase
    healthcheck:
      test: ["CMD-SHELL", "bash -c 'echo > /dev/tcp/localhost/6666'"]
      interval: 5s
      timeout: 3s
      retries: 10
      start_period: 5s

  coordinator:
    build:
      context: ../runtime
      dockerfile: Dockerfile.runtime
    image: opentenbase-runtime:latest
    container_name: opentenbase-coordinator
    hostname: coordinator
    depends_on:
      gtm:
        condition: service_healthy
    environment:
      - NODE_TYPE=coordinator
      - NODE_NAME=coordinator
      - GTM_HOST=gtm
      - GTM_PORT=6666
      - COORD_HOST=coordinator
      - COORD_PORT=5432
    ports:
      - "5432:5432"
    volumes:
      - coord_data:/var/lib/opentenbase/data/coordinator
    networks:
      - opentenbase
    healthcheck:
      test: ["CMD-SHELL", "bash -c 'echo > /dev/tcp/localhost/5432'"]
      interval: 5s
      timeout: 3s
      retries: 20
      start_period: 10s

  datanode1:
    build:
      context: ../runtime
      dockerfile: Dockerfile.runtime
    image: opentenbase-runtime:latest
    container_name: opentenbase-datanode1
    hostname: datanode1
    depends_on:
      gtm:
        condition: service_healthy
    environment:
      - NODE_TYPE=datanode
      - NODE_NAME=datanode1
      - GTM_HOST=gtm
      - GTM_PORT=6666
      - COORD_HOST=coordinator
      - COORD_PORT=5432
      - DN_PORT=15432
    ports:
      - "15432:15432"
    volumes:
      - dn1_data:/var/lib/opentenbase/data/datanode1
    networks:
      - opentenbase
    healthcheck:
      test: ["CMD-SHELL", "bash -c 'echo > /dev/tcp/localhost/15432'"]
      interval: 5s
      timeout: 3s
      retries: 20
      start_period: 10s

  datanode2:
    build:
      context: ../runtime
      dockerfile: Dockerfile.runtime
    image: opentenbase-runtime:latest
    container_name: opentenbase-datanode2
    hostname: datanode2
    depends_on:
      gtm:
        condition: service_healthy
    environment:
      - NODE_TYPE=datanode
      - NODE_NAME=datanode2
      - GTM_HOST=gtm
      - GTM_PORT=6666
      - COORD_HOST=coordinator
      - COORD_PORT=5432
      - DN_PORT=15433
    ports:
      - "15433:15433"
    volumes:
      - dn2_data:/var/lib/opentenbase/data/datanode2
    networks:
      - opentenbase
    healthcheck:
      test: ["CMD-SHELL", "bash -c 'echo > /dev/tcp/localhost/15433'"]
      interval: 5s
      timeout: 3s
      retries: 20
      start_period: 10s

volumes:
  gtm_data:
  coord_data:
  dn1_data:
  dn2_data:

networks:
  opentenbase:
    driver: bridge
COMPOSE

echo ""
echo "=========================================="
echo "文件准备完成！"
echo "=========================================="
echo ""
echo "目录结构:"
echo "  /tmp/otb-docker/"
echo "  ├── runtime/"
echo "  │   ├── Dockerfile.runtime"
echo "  │   ├── entrypoint.sh"
echo "  │   └── *.deb (4个包)"
echo "  └── compose/"
echo "      └── docker-compose.yml"
echo ""
echo "启动集群:"
echo "  cd /tmp/otb-docker/compose"
echo "  docker compose up -d --build"
echo ""
echo "查看状态:"
echo "  docker compose ps"
echo ""
echo "连接 Coordinator:"
echo "  docker compose exec coordinator psql -h 127.0.0.1 -U opentenbase -d postgres"
echo ""
echo "停止集群:"
echo "  docker compose down -v"
echo ""
