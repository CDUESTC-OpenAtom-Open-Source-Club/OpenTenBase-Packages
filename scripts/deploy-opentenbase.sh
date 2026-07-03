#!/bin/bash
# OpenTenBase 一键部署脚本
# 白板机器一条命令完成安装到集群运行
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/deploy-opentenbase.sh | sudo bash
#   # 非交互式
#   curl -sSL ... | sudo bash -s -- --yes
#   # 自定义参数
#   sudo bash deploy-opentenbase.sh --yes --cluster-name mycluster --ssh-password mypass

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# 默认参数
YES_MODE=false
CLUSTER_NAME="otb_cluster"
SSH_USER="opentenbase"
SSH_PASSWORD=""
SSH_PORT=22
GTM_IP=""
CN_IP=""
DN_IPS=""
VERSION="5.0"

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --yes|-y)          YES_MODE=true; shift ;;
        --cluster-name)    CLUSTER_NAME="$2"; shift 2 ;;
        --ssh-user)        SSH_USER="$2"; shift 2 ;;
        --ssh-password)    SSH_PASSWORD="$2"; shift 2 ;;
        --ssh-port)        SSH_PORT="$2"; shift 2 ;;
        --gtm-ip)          GTM_IP="$2"; shift 2 ;;
        --cn-ip)           CN_IP="$2"; shift 2 ;;
        --dn-ips)          DN_IPS="$2"; shift 2 ;;
        --version)         VERSION="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# 检查 root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "需要 root 权限"
        echo "请使用: sudo bash $0"
        exit 1
    fi
}

# 检测系统
detect_os() {
    if [ -f /etc/debian_version ]; then
        OS_FAMILY="debian"
        INSTALL_CMD="apt"
    elif [ -f /etc/redhat-release ]; then
        OS_FAMILY="redhat"
        INSTALL_CMD="dnf"
    else
        log_error "不支持的系统"
        exit 1
    fi
    log_info "检测到: $OS_FAMILY 系统"
}

# 系统准备
system_prepare() {
    log_step "系统准备..."

    # 安装必要工具
    if [ "$OS_FAMILY" = "debian" ]; then
        apt-get update -qq
        apt-get install -y -qq curl sshpass
    else
        dnf install -y -q curl sshpass || yum install -y -q curl sshpass
    fi

    # 检查内存
    MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    if [ "$MEM_TOTAL" -lt 3000 ]; then
        log_warn "内存不足 3GB (当前 $MEM_TOTAL MB)，可能存在问题"
        if [ "$YES_MODE" = "false" ]; then
            read -p "是否继续？[y/N] " -n 1 -r
            [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
        fi
    fi

    # 检查 CPU
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -le 2 ]; then
        log_warn "CPU 核心数 <= 2，GTM 线程绑定需要 patch（已包含在包中）"
    fi

    log_info "系统准备完成: CPU $CPU_CORES 核, 内存 $MEM_TOTAL MB"
}

# 安装 OpenTenBase
install_opentenbase() {
    log_step "安装 OpenTenBase $VERSION..."

    if [ "$OS_FAMILY" = "debian" ]; then
        # 配置 APT 仓库
        curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | bash -s -- --version $VERSION
        apt-get update -qq
        apt-get install -y -qq opentenbase opentenbase-server opentenbase-client opentenbase-contrib
    else
        # 配置 RPM 仓库
        curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh | bash
        dnf install -y -q opentenbase || yum install -y -q opentenbase
    fi

    log_info "OpenTenBase $VERSION 安装完成"
}

# 创建用户
create_user() {
    log_step "创建 opentenbase 用户..."

    if ! id opentenbase &>/dev/null; then
        useradd -m -s /bin/bash opentenbase
        log_info "用户 opentenbase 已创建"
    else
        log_info "用户 opentenbase 已存在"
    fi

    # 设置密码
    if [ -z "$SSH_PASSWORD" ]; then
        if [ "$YES_MODE" = "false" ]; then
            read -s -p "请输入 opentenbase 用户密码: " SSH_PASSWORD
            echo
        else
            SSH_PASSWORD="opentenbase123"
            log_warn "使用默认密码: opentenbase123"
        fi
    fi

    echo "opentenbase:$SSH_PASSWORD" | chpasswd
    log_info "用户密码已设置"
}

# 创建路径符号链接
create_symlinks() {
    log_step "创建路径符号链接..."

    mkdir -p /usr/local/install
    ln -sf /usr/lib/opentenbase/$VERSION /usr/local/install/opentenbase

    log_info "符号链接已创建: /usr/local/install/opentenbase -> /usr/lib/opentenbase/$VERSION"
}

# 生成配置文件
generate_config() {
    log_step "生成集群配置文件..."

    # 获取本机 IP
    if [ -z "$GTM_IP" ]; then
        GTM_IP=$(hostname -I | awk '{print $1}')
    fi
    if [ -z "$CN_IP" ]; then
        CN_IP="$GTM_IP"
    fi
    if [ -z "$DN_IPS" ]; then
        DN_IPS="$GTM_IP"
    fi

    CONFIG_FILE="/tmp/otb_config.ini"

    cat > "$CONFIG_FILE" << EOF
[instance]
name=$CLUSTER_NAME
type=distributed
package=/tmp/opentenbase-${VERSION}.tar.gz

[gtm]
master=$GTM_IP

[coordinators]
master=$CN_IP
nodes-per-server=1

[datanodes]
master=$DN_IPS
nodes-per-server=1

[server]
ssh-user=$SSH_USER
ssh-password=$SSH_PASSWORD
ssh-port=$SSH_PORT
EOF

    log_info "配置文件已生成: $CONFIG_FILE"
    log_info "GTM: $GTM_IP, CN: $CN_IP, DN: $DN_IPS"
}

# 创建部署包
create_package() {
    log_step "创建部署包 tar.gz..."

    OTB_DIR="/usr/lib/opentenbase/$VERSION"
    PKG_DIR="/tmp/otb-pkg"
    PKG_FILE="/tmp/opentenbase-${VERSION}.tar.gz"

    rm -rf "$PKG_DIR" "$PKG_FILE"
    mkdir -p "$PKG_DIR"
    cp -af "$OTB_DIR"/* "$PKG_DIR/"
    cd "$PKG_DIR"
    tar -zcf "$PKG_FILE" *
    cd /
    rm -rf "$PKG_DIR"

    log_info "部署包已创建: $PKG_FILE ($(du -h "$PKG_FILE" | cut -f1))"
}

# 安装集群
install_cluster() {
    log_step "安装集群..."

    export LD_LIBRARY_PATH=/usr/lib/opentenbase/$VERSION/lib:$LD_LIBRARY_PATH
    export PATH=/usr/lib/opentenbase/$VERSION/bin:$PATH

    opentenbase_ctl install -c /tmp/otb_config.ini

    log_info "集群安装完成"
}

# 启动集群
start_cluster() {
    log_step "启动集群..."

    opentenbase_ctl start

    log_info "集群启动完成"
}

# 验证
verify_cluster() {
    log_step "验证集群..."

    # 检查状态
    opentenbase_ctl status

    # 连接测试
    CN_PORT=11003
    if command -v opentenbase-psql &>/dev/null; then
        opentenbase-psql -h $CN_IP -p $CN_PORT -U opentenbase postgres -c "SELECT version();" || true
    fi

    log_info "验证完成"
}

# 显示结果
show_result() {
    echo ""
    echo "========================================"
    echo -e "${GREEN}  OpenTenBase 部署完成！${NC}"
    echo "========================================"
    echo ""
    echo "集群信息:"
    echo "  名称: $CLUSTER_NAME"
    echo "  GTM:  $GTM_IP:6666"
    echo "  CN:   $CN_IP:11003"
    echo "  DN:   $DN_IPS:15432"
    echo ""
    echo "连接数据库:"
    echo "  opentenbase-psql -h $CN_IP -p 11003 -U opentenbase postgres"
    echo ""
    echo "管理命令:"
    echo "  opentenbase_ctl status   # 查看状态"
    echo "  opentenbase_ctl stop     # 停止集群"
    echo "  opentenbase_ctl start    # 启动集群"
    echo ""
    echo "========================================"
}

# 主函数
main() {
    echo "========================================"
    echo "  OpenTenBase 一键部署脚本"
    echo "========================================"
    echo ""

    check_root
    detect_os
    system_prepare
    install_opentenbase
    create_user
    create_symlinks
    generate_config
    create_package
    install_cluster
    start_cluster
    verify_cluster
    show_result
}

main "$@"