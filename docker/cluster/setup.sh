#!/bin/bash
# OpenTenBase 分布式集群一键部署脚本
# 用法: bash setup.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 集群配置
GTM_IP="172.20.0.2"
CN_IP="172.20.0.3"
DN01_IP="172.20.0.4"
DN02_IP="172.20.0.5"
PORT=11000
FORWARD_PORT=6669
GTM_NAME="gtm0001"
CN_NAME="cn0001"
DN01_NAME="dn0001"
DN02_NAME="dn0002"

# ============================================================
# 1. 停止旧容器
# ============================================================
log "停止旧容器..."
docker-compose down -v 2>/dev/null || true
docker rm -f otb-gtm otb-cn otb-dn01 otb-dn02 2>/dev/null || true

# ============================================================
# 2. 创建空的 postgres.conf（如果不存在）
# ============================================================
if [ ! -f postgres.conf ]; then
    touch postgres.conf
fi

# ============================================================
# 3. 构建基础镜像
# ============================================================
log "构建基础镜像..."
docker build --network=host -f Dockerfile.centos -t opentenbase-cluster:latest . || err "镜像构建失败"

# ============================================================
# 4. 启动临时容器（用于安装集群）
# ============================================================
log "启动临时容器..."

cat > docker-compose.build.yml << EOF
version: '3.8'

networks:
  otb-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24

services:
  gtm:
    image: opentenbase-cluster:latest
    container_name: otb-gtm
    hostname: otb-gtm
    networks:
      otb-net:
        ipv4_address: ${GTM_IP}
    stdin_open: true
    tty: true
    command: bash -c "/usr/sbin/sshd && tail -f /dev/null"

  cn:
    image: opentenbase-cluster:latest
    container_name: otb-cn
    hostname: otb-cn
    networks:
      otb-net:
        ipv4_address: ${CN_IP}
    stdin_open: true
    tty: true
    command: bash -c "/usr/sbin/sshd && tail -f /dev/null"

  dn01:
    image: opentenbase-cluster:latest
    container_name: otb-dn01
    hostname: otb-dn01
    networks:
      otb-net:
        ipv4_address: ${DN01_IP}
    stdin_open: true
    tty: true
    command: bash -c "/usr/sbin/sshd && tail -f /dev/null"

  dn02:
    image: opentenbase-cluster:latest
    container_name: otb-dn02
    hostname: otb-dn02
    networks:
      otb-net:
        ipv4_address: ${DN02_IP}
    stdin_open: true
    tty: true
    command: bash -c "/usr/sbin/sshd && tail -f /dev/null"
EOF

docker-compose -f docker-compose.build.yml up -d || err "容器启动失败"

log "等待容器就绪..."
sleep 3

# ============================================================
# 5. 验证 SSH 连通性
# ============================================================
log "验证 SSH 连通性..."
for container in otb-gtm otb-cn otb-dn01 otb-dn02; do
    if ! docker exec -u opentenbase $container ssh -o ConnectTimeout=5 opentenbase@localhost echo "SSH OK" 2>/dev/null; then
        err "$container SSH 连接失败"
    fi
    log "  $container SSH OK"
done

# ============================================================
# 6. 安装集群（从 GTM 容器执行）
# ============================================================
log "安装集群（从 GTM 容器执行 opentenbase_ctl install）..."
docker exec -u opentenbase -w /data/opentenbase otb-gtm ./opentenbase_ctl install -c config.ini || err "集群安装失败"

# ============================================================
# 7. 初始化 GTM（opentenbase_ctl install 已完成此步骤）
# ============================================================
log "GTM 已由 opentenbase_ctl install 初始化"

# ============================================================
# 8. 初始化 CN/DN 数据目录（带 GTM 信息）
#    关键：必须指定 --master_gtm_nodename, --master_gtm_ip, --master_gtm_port
#    否则 pgxc_node 表中不会有 GTM 信息，CN/DN 无法连接 GTM
# ============================================================
log "初始化 CN/DN 数据目录..."

# 初始化 CN
docker exec -u opentenbase otb-cn bash -c "
  rm -rf /home/opentenbase/run/instance/opentenbase_cluster/${CN_NAME}/data/*
  export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib
  export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH
  cd /home/opentenbase/run/instance/opentenbase_cluster/${CN_NAME}/data
  initdb -D . --nodename=${CN_NAME} --nodetype=coordinator \
    --master_gtm_nodename=${GTM_NAME} --master_gtm_ip=${GTM_IP} --master_gtm_port=${PORT} 2>&1
" || err "CN initdb 失败"

# 初始化 DN01
docker exec -u opentenbase otb-dn01 bash -c "
  rm -rf /home/opentenbase/run/instance/opentenbase_cluster/${DN01_NAME}/data/*
  export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib
  export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH
  cd /home/opentenbase/run/instance/opentenbase_cluster/${DN01_NAME}/data
  initdb -D . --nodename=${DN01_NAME} --nodetype=datanode \
    --master_gtm_nodename=${GTM_NAME} --master_gtm_ip=${GTM_IP} --master_gtm_port=${PORT} 2>&1
" || err "DN01 initdb 失败"

# 初始化 DN02
docker exec -u opentenbase otb-dn02 bash -c "
  rm -rf /home/opentenbase/run/instance/opentenbase_cluster/${DN02_NAME}/data/*
  export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib
  export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH
  cd /home/opentenbase/run/instance/opentenbase_cluster/${DN02_NAME}/data
  initdb -D . --nodename=${DN02_NAME} --nodetype=datanode \
    --master_gtm_nodename=${GTM_NAME} --master_gtm_ip=${GTM_IP} --master_gtm_port=${PORT} 2>&1
" || err "DN02 initdb 失败"

# ============================================================
# 9. 配置 CN/DN 节点
# ============================================================
log "配置 CN/DN 节点..."

for node_info in "otb-cn:${CN_NAME}" "otb-dn01:${DN01_NAME}" "otb-dn02:${DN02_NAME}"; do
  container="${node_info%%:*}"
  node_name="${node_info##*:}"
  data_dir="/home/opentenbase/run/instance/opentenbase_cluster/${node_name}/data"

  # 配置 postgresql.conf
  docker exec -u opentenbase $container bash -c "
    sed -i \"s/^#listen_addresses.*/listen_addresses = '*'\" ${data_dir}/postgresql.conf
    grep -q '^port = ${PORT}' ${data_dir}/postgresql.conf || echo 'port = ${PORT}' >> ${data_dir}/postgresql.conf
  "

  # 配置 pg_hba.conf
  docker exec -u opentenbase $container bash -c "
    grep -q '172.20.0.0/24' ${data_dir}/pg_hba.conf || echo 'host all all 172.20.0.0/24 trust' >> ${data_dir}/pg_hba.conf
    grep -q '0.0.0.0/0' ${data_dir}/pg_hba.conf || echo 'host all all 0.0.0.0/0 md5' >> ${data_dir}/pg_hba.conf
  "
done

# ============================================================
# 10. 启动 GTM
# ============================================================
log "启动 GTM..."
docker exec -u opentenbase otb-gtm bash -c "
  export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib
  export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH
  gtm -D /home/opentenbase/run/instance/opentenbase_cluster/${GTM_NAME}/data -l /tmp/gtm.log &
" || err "GTM 启动失败"
sleep 2

# ============================================================
# 11. 启动 CN
# ============================================================
log "启动 CN..."
docker exec -u opentenbase otb-cn bash -c "
  export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib
  export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH
  pg_ctl -D /home/opentenbase/run/instance/opentenbase_cluster/${CN_NAME}/data -l /tmp/cn.log start -Z coordinator 2>&1
" || err "CN 启动失败"
sleep 3

# ============================================================
# 12. 设置 CN 的 forward_port（CN 可以直接 UPDATE pgxc_node）
# ============================================================
log "设置 CN 的 forward_port..."
docker exec -u opentenbase otb-cn bash -c "
  export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib
  export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH
  psql -h 127.0.0.1 -p ${PORT} -U opentenbase postgres -c \"UPDATE pgxc_node SET node_forward_port = ${FORWARD_PORT};\" 2>&1
" || err "CN forward_port 设置失败"

# ============================================================
# 13. 启动 DN01/DN02
# ============================================================
log "启动 DN01/DN02..."
docker exec -u opentenbase otb-dn01 bash -c "
  export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib
  export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH
  pg_ctl -D /home/opentenbase/run/instance/opentenbase_cluster/${DN01_NAME}/data -l /tmp/dn0001.log start -Z datanode 2>&1
" || err "DN01 启动失败"

docker exec -u opentenbase otb-dn02 bash -c "
  export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib
  export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH
  pg_ctl -D /home/opentenbase/run/instance/opentenbase_cluster/${DN02_NAME}/data -l /tmp/dn0002.log start -Z datanode 2>&1
" || err "DN02 启动失败"
sleep 3

# ============================================================
# 14. 在 DN 上注册所有节点（带 FORWARD 端口）
#     DN 的 pgxc_node 是只读的，需要用 DROP/CREATE NODE 来设置 forward_port
# ============================================================
log "在 DN 上注册所有节点..."

for dn_info in "otb-dn01:${DN01_NAME}:${DN01_IP}" "otb-dn02:${DN02_NAME}:${DN02_IP}"; do
  container="${dn_info%%:*}"
  remaining="${dn_info#*:}"
  dn_name="${remaining%%:*}"
  dn_ip="${remaining##*:}"

  # 确定另一个 DN 的信息
  if [ "$dn_name" = "$DN01_NAME" ]; then
    other_dn_name="$DN02_NAME"
    other_dn_ip="$DN02_IP"
  else
    other_dn_name="$DN01_NAME"
    other_dn_ip="$DN01_IP"
  fi

  docker exec -u opentenbase $container bash -c "
    export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib
    export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH
    psql -h 127.0.0.1 -p ${PORT} -U opentenbase postgres 2>&1 <<EOSQL
-- 重新注册 CN 节点（带 FORWARD 端口）
DROP NODE ${CN_NAME};
CREATE NODE ${CN_NAME} WITH (TYPE='coordinator', HOST='${CN_IP}', PORT=${PORT}, FORWARD=${FORWARD_PORT});
-- 重新注册另一个 DN 节点（带 FORWARD 端口）
DROP NODE ${other_dn_name};
CREATE NODE ${other_dn_name} WITH (TYPE='datanode', HOST='${other_dn_ip}', PORT=${PORT}, FORWARD=${FORWARD_PORT});
EOSQL
  " || warn "$dn_name 节点注册失败（可能需要先清理 shard）"
done

# ============================================================
# 15. 在 CN 上注册 DN 节点并创建节点组和 Shard Map
# ============================================================
log "在 CN 上注册 DN 节点并创建节点组..."

docker exec -u opentenbase otb-cn bash -c "
  export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib
  export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH
  psql -h 127.0.0.1 -p ${PORT} -U opentenbase postgres 2>&1 <<EOSQL
-- 注册 DN 节点
CREATE NODE ${DN01_NAME} WITH (TYPE='datanode', HOST='${DN01_IP}', PORT=${PORT}, FORWARD=${FORWARD_PORT});
CREATE NODE ${DN02_NAME} WITH (TYPE='datanode', HOST='${DN02_IP}', PORT=${PORT}, FORWARD=${FORWARD_PORT});
-- 创建默认节点组
CREATE DEFAULT NODE GROUP default_group WITH (${DN01_NAME}, ${DN02_NAME});
-- 初始化 Shard Map
CREATE SHARDING GROUP TO GROUP default_group;
-- 清理 Shard 缓存
CLEAN SHARDING;
EOSQL
" || err "节点组创建失败"

# ============================================================
# 16. 验证
# ============================================================
log "验证集群状态..."

# 检查 GTM
log "检查 GTM..."
docker exec -u opentenbase otb-gtm bash -c "
  export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib
  export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH
  ss -tlnp 2>/dev/null | grep ${PORT}
"

# 检查 CN
log "检查 CN..."
docker exec -u opentenbase otb-cn bash -c "
  export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib
  export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH
  pg_ctl -D /home/opentenbase/run/instance/opentenbase_cluster/${CN_NAME}/data status -Z coordinator 2>&1
"

# 测试 psql 连接和分布式查询
log "测试 psql 连接和分布式查询..."
sleep 2
docker exec -u opentenbase otb-cn bash -c "
  export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib
  export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH
  psql -h 127.0.0.1 -p ${PORT} -U opentenbase postgres 2>&1 <<EOSQL
SELECT node_name, node_type, node_host, node_port, node_forward_port FROM pgxc_node ORDER BY node_id;
SELECT count(*) as shard_count FROM pgxc_shard_map;
CREATE TABLE test_cluster (id int PRIMARY KEY, info text) DISTRIBUTE BY SHARD(id);
INSERT INTO test_cluster VALUES (1, 'OpenTenBase'), (2, 'Distributed'), (3, 'Database');
SELECT * FROM test_cluster ORDER BY id;
DROP TABLE test_cluster;
EOSQL
" || warn "psql 连接测试失败（可能需要等待节点就绪）"

# ============================================================
# 17. 提交镜像
# ============================================================
log "提交镜像..."
docker commit otb-gtm otb-gtm:installed
docker commit otb-cn otb-cn:installed
docker commit otb-dn01 otb-dn01:installed
docker commit otb-dn02 otb-dn02:installed

# ============================================================
# 18. 清理临时容器
# ============================================================
log "清理临时容器..."
docker-compose -f docker-compose.build.yml down
rm -f docker-compose.build.yml

# ============================================================
# 19. 创建最终的 docker-compose.yml
# ============================================================
log "创建最终的 docker-compose.yml..."
cat > docker-compose.yml << EOF
version: '3.8'

networks:
  otb-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24

services:
  # GTM 节点
  gtm:
    image: otb-gtm:installed
    container_name: otb-gtm
    hostname: otb-gtm
    networks:
      otb-net:
        ipv4_address: ${GTM_IP}
    stdin_open: true
    tty: true
    command: >
      bash -c "/usr/sbin/sshd &&
               su - opentenbase -c 'export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib && export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH && gtm -D /home/opentenbase/run/instance/opentenbase_cluster/${GTM_NAME}/data -l /tmp/gtm.log' &
               tail -f /dev/null"

  # CN 协调节点
  cn:
    image: otb-cn:installed
    container_name: otb-cn
    hostname: otb-cn
    networks:
      otb-net:
        ipv4_address: ${CN_IP}
    ports:
      - "${PORT}:${PORT}"
    depends_on:
      - gtm
    stdin_open: true
    tty: true
    command: >
      bash -c "/usr/sbin/sshd &&
               echo 'Waiting for GTM...' &&
               while ! (echo > /dev/tcp/${GTM_IP}/${PORT}) 2>/dev/null; do sleep 1; done &&
               echo 'GTM is ready' &&
               su - opentenbase -c 'export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib && export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH && pg_ctl -D /home/opentenbase/run/instance/opentenbase_cluster/${CN_NAME}/data -l /tmp/cn.log start -Z coordinator' &&
               tail -f /dev/null"

  # DN01 数据节点
  dn01:
    image: otb-dn01:installed
    container_name: otb-dn01
    hostname: otb-dn01
    networks:
      otb-net:
        ipv4_address: ${DN01_IP}
    depends_on:
      - gtm
    stdin_open: true
    tty: true
    command: >
      bash -c "/usr/sbin/sshd &&
               echo 'Waiting for GTM...' &&
               while ! (echo > /dev/tcp/${GTM_IP}/${PORT}) 2>/dev/null; do sleep 1; done &&
               echo 'GTM is ready' &&
               su - opentenbase -c 'export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib && export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH && pg_ctl -D /home/opentenbase/run/instance/opentenbase_cluster/${DN01_NAME}/data -l /tmp/dn0001.log start -Z datanode' &&
               tail -f /dev/null"

  # DN02 数据节点
  dn02:
    image: otb-dn02:installed
    container_name: otb-dn02
    hostname: otb-dn02
    networks:
      otb-net:
        ipv4_address: ${DN02_IP}
    depends_on:
      - gtm
    stdin_open: true
    tty: true
    command: >
      bash -c "/usr/sbin/sshd &&
               echo 'Waiting for GTM...' &&
               while ! (echo > /dev/tcp/${GTM_IP}/${PORT}) 2>/dev/null; do sleep 1; done &&
               echo 'GTM is ready' &&
               su - opentenbase -c 'export LD_LIBRARY_PATH=/home/opentenbase/install/opentenbase/5.0/lib && export PATH=/home/opentenbase/install/opentenbase/5.0/bin:\$PATH && pg_ctl -D /home/opentenbase/run/instance/opentenbase_cluster/${DN02_NAME}/data -l /tmp/dn0002.log start -Z datanode' &&
               tail -f /dev/null"
EOF

# ============================================================
# 20. 启动集群
# ============================================================
log "启动集群..."
docker-compose up -d || err "集群启动失败"

# 等待集群就绪
log "等待集群就绪..."
sleep 5

log "=========================================="
log "集群部署完成！"
log "=========================================="
log "连接数据库: psql -h 127.0.0.1 -p ${PORT} -U opentenbase postgres"
log "查看状态:   docker exec -u opentenbase otb-cn psql -h 127.0.0.1 -p ${PORT} -U opentenbase postgres -c 'SELECT * FROM pgxc_node;'"
log "停止集群:   docker-compose down"
log "启动集群:   docker-compose up -d"
log "=========================================="
