#!/bin/bash
# OpenTenBase Docker Compose 一键部署测试脚本
# 自动检测架构 (x86_64/aarch64) 并下载对应的 RPM 包
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

# 自动检测架构
ARCH=$(uname -m)
echo "检测到架构: $ARCH"

# 设置下载链接和包名
RELEASE_TAG="v5.0-multi13"
BASE_URL="https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/${RELEASE_TAG}"

# 根据架构选择 RPM 包
if [ "$ARCH" = "aarch64" ]; then
    # aarch64: 使用 openeuler 包
    RPM_DISTRO="openeuler-22.03-aarch64"
    # 尝试多个可能的包名格式
    RPM_CANDIDATES=(
        "opentenbase-5.0-1.${RPM_DISTRO}.aarch64.rpm"
        "opentenbase-5.0-1.aarch64.${RPM_DISTRO}.rpm"
    )
    echo "使用 aarch64 RPM 包 (openeuler)"
elif [ "$ARCH" = "x86_64" ]; then
    # x86_64: 使用 rockylinux 包
    RPM_DISTRO="rockylinux-8-x86_64"
    RPM_CANDIDATES=(
        "opentenbase-5.0-1.${RPM_DISTRO}.x86_64.rpm"
        "opentenbase-5.0-1.x86_64.${RPM_DISTRO}.rpm"
    )
    echo "使用 x86_64 RPM 包 (rockylinux)"
else
    echo "ERROR: 不支持的架构: $ARCH"
    exit 1
fi

# 创建工作目录
echo "[1/5] 创建目录结构..."
mkdir -p /tmp/otb-docker/runtime/extracted /tmp/otb-docker/compose

# 下载 RPM 包
echo "[2/5] 下载 RPM 包..."
cd /tmp/otb-docker/runtime
RPM_FILE=""
for rpm in "${RPM_CANDIDATES[@]}"; do
    echo "  尝试下载 $rpm..."
    if curl -sL -f -o "$rpm" "${BASE_URL}/${rpm}" 2>/dev/null; then
        RPM_FILE="$rpm"
        echo "  成功下载: $rpm"
        break
    else
        echo "  不存在: $rpm"
        rm -f "$rpm"
    fi
done

if [ -z "$RPM_FILE" ]; then
    echo ""
    echo "ERROR: 无法下载 RPM 包。"
    echo "请检查 GitHub Releases 是否有 $ARCH 架构的包:"
    echo "  ${BASE_URL}"
    echo ""
    echo "可用的 x86_64 包:"
    curl -sL "https://api.github.com/repos/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tags/${RELEASE_TAG}" | \
        grep -o '"name": "[^"]*rpm"' | grep -i "$ARCH" || echo "  (无)"
    exit 1
fi

# 解压 RPM 包到 extracted/ 目录
echo "[3/5] 解压 RPM 包..."
cd /tmp/otb-docker/runtime
rm -rf extracted
mkdir -p extracted
# rpm2cpio 解压到 extracted 目录
rpm2cpio "$RPM_FILE" | (cd extracted && cpio -idm 2>/dev/null || true)
echo "  解压完成"
ls -la extracted/usr/lib/opentenbase/5.0/bin/ 2>/dev/null | head -5 || echo "  WARNING: 未找到 bin 目录"

# 复制 Dockerfile 和 entrypoint
echo "[4/5] 准备构建文件..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/runtime/Dockerfile.runtime" ]; then
    cp "$SCRIPT_DIR/runtime/Dockerfile.runtime" /tmp/otb-docker/runtime/
else
    echo "  使用仓库中的 Dockerfile.runtime"
fi
if [ -f "$SCRIPT_DIR/runtime/entrypoint.sh" ]; then
    cp "$SCRIPT_DIR/runtime/entrypoint.sh" /tmp/otb-docker/runtime/
else
    echo "  使用仓库中的 entrypoint.sh"
fi

# 创建 docker-compose.yml
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
    security_opt:
      - apparmor:unconfined
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
    security_opt:
      - apparmor:unconfined
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
    security_opt:
      - apparmor:unconfined
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
    security_opt:
      - apparmor:unconfined
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
echo "  │   ├── $RPM_FILE"
echo "  │   └── extracted/ (RPM 解压内容)"
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
