#!/bin/bash
# OpenTenBase 一键安装脚本 - 安装 + 配置 + 启动
# 使用方法: curl -sSL https://get.opentenbase.com | sudo bash
#
# 安装完成后，用户只需要两条命令:
#   opentenbase init    # 初始化单节点集群
#   opentenbase start   # 启动服务
#
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[OpenTenBase]${NC} $1"; }
warn() { echo -e "${YELLOW}[警告]${NC} $1"; }
err() { echo -e "${RED}[错误]${NC} $1"; exit 1; }

# 必须root运行
[ "$(id -u)" -ne 0 ] && err "请使用 sudo 运行此脚本"

# 检测系统
if [ ! -f /etc/os-release ]; then err "无法检测操作系统"; fi
. /etc/os-release

# ===== 第一步: 配置软件源 =====
log "正在配置软件源..."

# GPG密钥指纹
FINGERPRINT="D8B2E316E1FF88EE178703549D8FA46F3A55D5F0"
KEYRING="/usr/share/keyrings/opentenbase.gpg"
REPO_URL="https://repo.blackevil217.com"

# 确定系统类型
case "$ID" in
    ubuntu|debian|linuxmint|pop)
        # DEB 系统
        CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
        [ -z "$CODENAME" ] && CODENAME="noble"

        # 下载并验证GPG密钥
        curl -sL "$REPO_URL/apt/gpg-key.asc" | gpg --dearmor > "$KEYRING"

        # 配置APT源
        echo "deb [signed-by=$KEYRING] $REPO_URL/apt $CODENAME main v2.6 v2.5" \
            > /etc/apt/sources.list.d/opentenbase.list

        apt-get update -qq
        log "软件源配置完成"

        # 安装libpqxx依赖 (Ubuntu 24.04需要)
        ARCH=$(dpkg --print-architecture)
        if ! apt-cache show libpqxx-dev 2>/dev/null | grep -q "Version: 7.9"; then
            log "正在安装libpqxx依赖..."
            curl -sL "$REPO_URL/deps/libpqxx-7.9_7.9.2-1~${CODENAME}_${ARCH}.deb" \
                -o /tmp/libpqxx.deb
            curl -sL "$REPO_URL/deps/libpqxx-7.9-dev_7.9.2-1~${CODENAME}_${ARCH}.deb" \
                -o /tmp/libpqxx-dev.deb
            apt-get install -y libpq5 || true
            dpkg -i /tmp/libpqxx.deb /tmp/libpqxx-dev.deb || apt-get install -y -f
            rm -f /tmp/libpqxx*.deb
        fi

        # 安装OpenTenBase
        log "正在安装OpenTenBase..."
        apt-get install -y opentenbase

        ;;
    rocky|almalinux|centos|rhel|fedora|openeuler|opencloudos)
        # RPM 系统
        case "$VERSION_ID" in
            8*) REPO_VER="el8" ;;
            9*) REPO_VER="el9" ;;
            *)  REPO_VER="el9" ;;
        esac
        ARCH=$(uname -m)

        # 导入GPG密钥
        rpm --import "$REPO_URL/rpm/gpg-key.asc"

        # 配置YUM源
        cat > /etc/yum.repos.d/opentenbase.repo << EOF
[opentenbase]
name=OpenTenBase
baseurl=$REPO_URL/rpm/$REPO_VER/$ARCH
enabled=1
gpgcheck=1
EOF

        dnf makecache -q || yum makecache -q
        log "软件源配置完成"

        # 安装OpenTenBase
        log "正在安装OpenTenBase..."
        dnf install -y opentenbase || yum install -y opentenbase
        ;;
    *)
        err "不支持的系统: $ID"
        ;;
esac

# ===== 第二步: 创建opentenbase用户 =====
log "正在配置用户..."
if ! id opentenbase &>/dev/null; then
    useradd -r -m -d /var/lib/opentenbase -s /bin/bash opentenbase
fi
mkdir -p /var/lib/opentenbase/5.0 /var/log/opentenbase/5.0 /var/run/opentenbase
chown -R opentenbase:opentenbase /var/lib/opentenbase /var/log/opentenbase

# ===== 第三步: 创建简化命令 =====
log "正在配置简化命令..."

# 创建 opentenbase 简化命令
cat > /usr/local/bin/opentenbase << 'OTB_CMD'
#!/bin/bash
# OpenTenBase 简化命令
# 用法:
#   opentenbase init    - 初始化单节点集群
#   opentenbase start   - 启动集群
#   opentenbase stop    - 停止集群
#   opentenbase status  - 查看状态
#   opentenbase sql     - 连接数据库

OTB_HOME="/usr/lib/opentenbase/5.0"
OTB_CTL="$OTB_HOME/bin/opentenbase_ctl"
INI="/etc/opentenbase/5.0/opentenbase.ini"

init_cluster() {
    echo "正在初始化OpenTenBase单节点集群..."

    # 创建最小配置
    mkdir -p /etc/opentenbase/5.0
    cat > "$INI" << EOF
[GTMS]
nodename=gtm
listen=127.0.0.1
port=6666
dir=/var/lib/opentenbase/5.0/gtm

[COORDINATORS]
nodename=coord1
listen=127.0.0.1
port=5432
pooler_port=6667
dir=/var/lib/opentenbase/5.0/coord
EOF

    # 添加数据节点
    echo "[DATANODES]" >> "$INI"
    echo "nodename=dn1" >> "$INI"
    echo "listen=127.0.0.1" >> "$INI"
    echo "port=15432" >> "$INI"
    echo "pooler_port=6668" >> "$INI"
    echo "dir=/var/lib/opentenbase/5.0/dn1" >> "$INI"

    # 初始化各节点
    echo "初始化 GTM..."
    $OTB_CTL init gtm --dir /var/lib/opentenbase/5.0/gtm -Z gtm -D /var/lib/opentenbase/5.0/gtm 2>/dev/null || true

    echo "初始化 Coordinator..."
    $OTB_CTL init coord1 --dir /var/lib/opentenbase/5.0/coord -Z coordinator -D /var/lib/opentenbase/5.0/coord -n coord1 --with_gtm --gtm_nodename gtm --gtm_host 127.0.0.1 --gtm_port 6666 2>/dev/null || true

    echo "初始化 Datanode..."
    $OTB_CTL init dn1 --dir /var/lib/opentenbase/5.0/dn1 -Z datanode -D /var/lib/opentenbase/5.0/dn1 -n dn1 --with_gtm --gtm_nodename gtm --gtm_host 127.0.0.1 --gtm_port 6666 2>/dev/null || true

    chown -R opentenbase:opentenbase /var/lib/opentenbase /var/log/opentenbase

    echo "✓ 集群初始化完成！"
}

case "$1" in
    init)
        init_cluster
        ;;
    start)
        echo "启动 OpenTenBase..."
        $OTB_CTL start all
        echo "✓ 服务已启动"
        ;;
    stop)
        echo "停止 OpenTenBase..."
        $OTB_CTL stop all
        echo "✓ 服务已停止"
        ;;
    status)
        $OTB_CTL show status all
        ;;
    sql)
        PSQL="$OTB_HOME/bin/psql"
        $PSQL -h 127.0.0.1 -p 5432 -U opentenbase -d postgres
        ;;
    *)
        echo "用法: opentenbase <命令>"
        echo ""
        echo "命令:"
        echo "  init    初始化单节点集群"
        echo "  start   启动集群"
        echo "  stop    停止集群"
        echo "  status  查看状态"
        echo "  sql     连接数据库"
        ;;
esac
OTB_CMD

chmod +x /usr/local/bin/opentenbase

# ===== 完成 =====
echo ""
echo "========================================"
echo -e "${GREEN}  OpenTenBase 安装完成！${NC}"
echo "========================================"
echo ""
echo "现在你可以使用以下命令:"
echo ""
echo "  opentenbase init     # 初始化集群"
echo "  opentenbase start    # 启动服务"
echo "  opentenbase status   # 查看状态"
echo "  opentenbase sql      # 连接数据库"
echo ""
echo "========================================"