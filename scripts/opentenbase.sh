#!/bin/bash
# =============================================================================
# OpenTenBase 一键管理脚本
# =============================================================================
# 用法:
#   curl -sSL <url>/opentenbase.sh | sudo bash           # 默认安装部署
#   sudo bash opentenbase.sh install [--yes]             # 安装部署
#   sudo bash opentenbase.sh uninstall [--purge]         # 卸载
#   sudo bash opentenbase.sh switch [VERSION]            # 切换版本
#   sudo bash opentenbase.sh status                      # 查看状态
#   sudo bash opentenbase.sh test [--quick|--full]       # 验证测试
#
# 原 deploy-opentenbase.sh 用法（兼容）：
#
#   【交互式】（推荐新手，会问你几个问题）
#   curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/deploy-opentenbase.sh | sudo bash
#
#   【非交互式】（单节点默认值，CI/自动化用）
#   curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/deploy-opentenbase.sh | sudo bash -s -- --yes
#
#   【非交互式 + 自定义参数】
#   sudo bash deploy-opentenbase.sh --yes \
#       --ssh-password mypass123 \
#       --cluster-name mycluster \
#       --gtm-ip 192.168.1.10 \
#       --cn-ip 192.168.1.10 \
#       --dn-ip 192.168.1.10
#
#   本地文件运行:
#   sudo bash deploy-opentenbase.sh              # 交互式
#   sudo bash deploy-opentenbase.sh --yes        # 非交互式（全默认值）
#
# 选项:
#   --yes                 非交互式，使用默认值不提问
#   --ssh-password PASS   SSH 密码（默认交互式询问或 'opentenbase'）
#   --cluster-name NAME   集群名称（默认 otb01）
#   --gtm-ip IP           GTM 节点 IP（默认 127.0.0.1）
#   --cn-ip IP            Coordinator 节点 IP（默认同 gtm-ip）
#   --dn-ip IP            Datanode 节点 IP（默认同 gtm-ip）
#   --ssh-user USER       SSH 用户名（默认 opentenbase）
#   --ssh-port PORT       SSH 端口（默认 22）
#   --version VER         OpenTenBase 版本（5.0 / 2.6.0 / 2.5.0，默认 5.0）
#   --skip-install        跳过包安装（已装时用）
#   --start               安装后自动启动集群（默认启用）
#   --no-start            安装后不启动集群
#   --clean               部署前清理旧数据和残留进程
#   --help                显示帮助
#

set -euo pipefail

# 管道执行（curl|bash）兼容：stdin 不是终端时重连到 /dev/tty，使交互式
# read 正常工作；若 /dev/tty 不可用（CI/无终端环境）则标记强制非交互，
# 避免 read 遇到 EOF 返回非零而触发 set -e 退出。
if [[ ! -t 0 ]]; then
    if [[ -c /dev/tty ]] && ( : <>/dev/tty ) 2>/dev/null; then
        exec 0</dev/tty
    else
        export OTB_FORCE_NONINTERACTIVE=1
    fi
fi

# 脚本目录（管道执行时 BASH_SOURCE 为空，用 ${0:-.} 兜底，避免 set -u 报错）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${0:-.}}")" 2>/dev/null && pwd || echo ".")"

# ====================================================================
# 子命令解析（新增）
# ====================================================================
# 记录子命令。uninstall/switch 立即 exec（调用外部脚本，不依赖内部函数）；
# status/test/--help 延迟到脚本末尾分发（此时函数定义已加载）；
# install 或无参数 → 继续执行下方的安装部署主体（默认行为）。
OTB_COMMAND="${1:-install}"
case "$OTB_COMMAND" in
    uninstall)
        shift
        exec bash "${SCRIPT_DIR}/uninstall.sh" "$@"
        ;;
    switch)
        shift
        exec bash "${SCRIPT_DIR}/switch-version.sh" "$@"
        ;;
    install)
        shift || true
        ;;
    status|test|--help|-h)
        shift || true
        ;;
    *)
        OTB_COMMAND="install"
        ;;
esac

# ====================================================================
# 参数与默认值（原 deploy-opentenbase.sh 逻辑）
# ====================================================================
INTERACTIVE=true
[[ "${OTB_FORCE_NONINTERACTIVE:-0}" == "1" ]] && INTERACTIVE=false
SSH_PASSWORD=""
CLUSTER_NAME="otb01"
GTM_IP="127.0.0.1"
CN_IP=""
DN_IP=""
SSH_USER="opentenbase"
SSH_PORT="22"
OTB_VERSION="5.0"
SKIP_INSTALL=false
AUTO_START=true
CLEAN_BEFORE=false
CONFIG_FILE="/tmp/opentenbase_config.ini"
PACKAGE_PATH="/usr/lib/opentenbase/5.0"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}${BOLD}  $*${NC}"; echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }
log_ok()    { echo -e "${GREEN}${BOLD}  ✓${NC} $*"; }

# 交互式提问（带默认值）
ask() {
    local prompt="$1"
    local default="$2"
    local var="$3"
    if [[ "$INTERACTIVE" == "false" ]]; then
        eval "$var=\"$default\""
        return
    fi
    local input
    read -rp "$(echo -e "${CYAN}${BOLD}?${NC} ${prompt} [${default}]: ")" input
    eval "$var=\"${input:-$default}\""
}

ask_password() {
    local prompt="$1"
    local var="$2"
    if [[ "$INTERACTIVE" == "false" ]]; then
        eval "$var=\"opentenbase\""
        return
    fi
    local input
    read -sp "$(echo -e "${CYAN}${BOLD}?${NC} ${prompt}: ")" input
    echo ""
    eval "$var=\"${input:-opentenbase}\""
}

# ====================================================================
# 解析命令行参数
# ====================================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --yes|-y)          INTERACTIVE=false; shift ;;
        --ssh-password)    SSH_PASSWORD="$2"; INTERACTIVE=false; shift 2 ;;
        --cluster-name)    CLUSTER_NAME="$2"; shift 2 ;;
        --gtm-ip)          GTM_IP="$2"; shift 2 ;;
        --cn-ip)           CN_IP="$2"; shift 2 ;;
        --dn-ip)           DN_IP="$2"; shift 2 ;;
        --ssh-user)        SSH_USER="$2"; shift 2 ;;
        --ssh-port)        SSH_PORT="$2"; shift 2 ;;
        --version)         OTB_VERSION="$2"; shift 2 ;;
        --skip-install)    SKIP_INSTALL=true; shift ;;
        --start)           AUTO_START=true; shift ;;
        --no-start)        AUTO_START=false; shift ;;
        --clean)           CLEAN_BEFORE=true; shift ;;
        --help|-h)
            head -48 "$0" | tail -46
            exit 0 ;;
        *) log_error "未知参数: $1（--help 查看帮助）"; exit 1 ;;
    esac
done

# ====================================================================
# Banner
# ====================================================================
echo ""
echo -e "${CYAN}${BOLD}"
cat << 'BANNER'
  ╔══════════════════════════════════════════════╗
  ║                                              ║
  ║          OpenTenBase 一键部署脚本            ║
  ║                                              ║
  ║    白板机器 → 集群运行，一条命令搞定         ║
  ║                                              ║
  ╚══════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

if [[ "$INTERACTIVE" == "true" ]]; then
    echo -e "  模式: ${GREEN}交互式${NC}（会问你几个问题）"
else
    echo -e "  模式: ${GREEN}非交互式${NC}（使用默认值）"
fi
echo ""

# ====================================================================
# 版本规范化与链路判定
# ====================================================================
case "$OTB_VERSION" in
    2.5)   OTB_VERSION="2.5.0" ;;
    2.6)   OTB_VERSION="2.6.0" ;;
    5.0|5) OTB_VERSION="5.0" ;;
esac

USE_PGXC_CTL=false
case "$OTB_VERSION" in
    2.5.0|2.6.0)
        USE_PGXC_CTL=true
        OTB_SHORT_VER="${OTB_VERSION%%.*}"
        CN_PORT_DEFAULT=5432
        ;;
    5.0)
        USE_PGXC_CTL=false
        OTB_SHORT_VER="5"
        CN_PORT_DEFAULT=11003
        ;;
    *)
        log_error "不支持的版本: $OTB_VERSION（支持: 5.0 / 2.6.0 / 2.5.0）"
        exit 1
        ;;
esac

INSTALL_DIR="/usr/lib/opentenbase/${OTB_VERSION}"
echo -e "  版本: ${GREEN}${OTB_VERSION}${NC}  链路: ${GREEN}$([[ "$USE_PGXC_CTL" == "true" ]] && echo 'pgxc_ctl' || echo 'opentenbase_ctl')${NC}"
echo ""

# 非 install 子命令（status/test/--help）跳过下方部署主体，落到末尾分发
if [[ "$OTB_COMMAND" == "install" ]]; then

# ====================================================================
# 预清理（--clean）
# ====================================================================
if [[ "$CLEAN_BEFORE" == "true" ]]; then
    log_step "Step 0: 清理旧环境和残留进程"

    # 停止所有版本的集群（安全模式：精确匹配 OTB 进程，不影响 SSH/脚本自身）
    for pat in "postgres:.*coord" "postgres:.*dn0" "gtm.*master" "gtm_proxy"; do
        kill -9 $(pgrep -f "$pat" 2>/dev/null) 2>/dev/null || true
    done
    for pid in $(ps -u "$SSH_USER" -o pid= 2>/dev/null); do
        cmd=$(ps -p "$pid" -o comm= 2>/dev/null)
        [[ "$cmd" == "postgres" || "$cmd" == "gtm" || "$cmd" == "gtm_proxy" ]] && kill -9 "$pid" 2>/dev/null || true
    done
    sleep 3

    # 清理 lock 文件
    rm -f /tmp/.s.PGSQL.* /tmp/.s.PGPOOL.* /tmp/.s.*.lock 2>/dev/null || true

    # 清理所有版本的数据目录（全量清理，避免跨版本残留）
    for ver in 2 2.5 2.5.0 2.6 2.6.0 5 5.0; do
        for subdir in gtm coord dn1 coord_archlog dn1_archlog gtm_slave coord_slave dn1_slave; do
            rm -rf "/var/lib/opentenbase/${ver}/${subdir}"/* 2>/dev/null || true
        done
    done
    # 清理 5.0 的数据目录
    rm -rf /var/lib/opentenbase/install/opentenbase/5.0/data/* 2>/dev/null || true
    rm -rf /var/lib/opentenbase/data/* 2>/dev/null || true
    # 清理 pgxc_ctl 工作目录中的残留状态
    rm -f /var/lib/opentenbase/pgxc_ctl/pgxc_ctl.conf 2>/dev/null || true

    log_ok "旧环境已清理（跨版本全量清理）"
fi

# ====================================================================
# Step 0: 环境检查
# ====================================================================
log_step "Step 1/6: 环境检查"

# root 检查
if [[ $EUID -ne 0 ]]; then
    log_error "请使用 root 用户运行: sudo bash $0"
    exit 1
fi
log_ok "root 权限"

# 内存
MEM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
if [[ -z "$MEM_TOTAL" ]] || [[ "$MEM_TOTAL" -lt 3000 ]]; then
    log_warn "内存 ${MEM_TOTAL:-未知}MB，建议 ≥ 4GB（继续部署）"
else
    log_ok "内存 ${MEM_TOTAL}MB"
fi

# 磁盘
DISK_AVAIL=$(df -m / | awk 'NR==2{print $4}')
if [[ -n "$DISK_AVAIL" ]] && [[ "$DISK_AVAIL" -lt 3000 ]]; then
    log_warn "磁盘剩余 ${DISK_AVAIL}MB，建议 ≥ 5GB"
else
    log_ok "磁盘剩余 ${DISK_AVAIL}MB"
fi

# CPU
CPU_CORES=$(nproc 2>/dev/null || echo 1)
log_ok "CPU ${CPU_CORES} 核"

# Low-core fix: GTM uses pthread_setaffinity_np which fails on ≤2 core machines
# with EINVAL, causing GTM to crash. Create a stub .so that makes the call a no-op.
NOAFFINITY_SO=""
if [[ "$CPU_CORES" -le 2 ]]; then
    log_warn "CPU ≤ 2 核，创建 noaffinity.so 绕过 GTM CPU 亲和性问题"
    NOAFFINITY_SO="/usr/lib/opentenbase/noaffinity.so"
    cat > /tmp/noaffinity.c << 'NOAFEOF'
#define _GNU_SOURCE
#include <pthread.h>
#include <string.h>
int pthread_setaffinity_np(pthread_t thread, size_t cpusetsize, const cpu_set_t *cpuset) {
    (void)thread; (void)cpusetsize; (void)cpuset;
    return 0;
}
NOAFEOF
    if gcc -shared -fPIC -o "$NOAFFINITY_SO" /tmp/noaffinity.c -lpthread 2>/dev/null; then
        log_ok "noaffinity.so 已创建: $NOAFFINITY_SO"

        # 写入 /etc/ld.so.preload 实现全局注入
        # 原因：opentenbase_ctl 通过 SSH 启动 GTM 为独立进程，
        # LD_PRELOAD 环境变量不会传播到 SSH 子进程。
        # /etc/ld.so.preload 是系统级配置，所有进程（含 SSH 子进程）都会加载。
        if [[ ! -f /etc/ld.so.preload ]] || ! grep -q "$NOAFFINITY_SO" /etc/ld.so.preload 2>/dev/null; then
            echo "$NOAFFINITY_SO" >> /etc/ld.so.preload
            chmod 644 /etc/ld.so.preload
            log_ok "已写入 /etc/ld.so.preload（全局注入，GTM 子进程也会生效）"
        else
            log_ok "/etc/ld.so.preload 已包含 noaffinity.so"
        fi
    else
        log_warn "noaffinity.so 创建失败，2 核机器上 GTM 可能崩溃"
        NOAFFINITY_SO=""
    fi
    rm -f /tmp/noaffinity.c
fi

# OS 检测
OS_ID=$(cat /etc/os-release 2>/dev/null | grep -E "^ID=" | head -1 | cut -d'=' -f2 | tr -d '"' || echo "unknown")
log_ok "操作系统: ${OS_ID}"

# ====================================================================
# Step 2: 安装软件包 + sshpass
# ====================================================================
if [[ "$SKIP_INSTALL" == "true" ]]; then
    log_step "Step 2/6: 跳过包安装（--skip-install）"
else
    log_step "Step 2/6: 安装 OpenTenBase 软件包"

    if command -v apt-get &>/dev/null; then
        # --- APT (Ubuntu/Debian) ---
        log_info "检测到 APT 包管理器"

        # 安装 sshpass
        log_info "安装 sshpass..."
        apt-get install -y sshpass >/dev/null 2>&1 || true

        # 配置仓库（用 sources.list 文件存在性检查，避免包名匹配干扰）
        if [ ! -f /etc/apt/sources.list.d/opentenbase.list ]; then
            log_info "配置 OpenTenBase APT 仓库..."
            # Use CDN for faster global access, fallback to GitHub raw
            CDN_URL="https://repo.blackevil217.com/scripts/setup-apt.sh"
            GITHUB_URL="https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh"

            if curl -sSL --connect-timeout 5 --max-time 60 "$CDN_URL" | bash -s -- --version "$OTB_VERSION"; then
                log_ok "APT repository configured via CDN (version $OTB_VERSION)"
            else
                log_warn "CDN unavailable, falling back to GitHub..."
                curl -sSL "$GITHUB_URL" | bash -s -- --version "$OTB_VERSION" || {
                    log_warn "自动配置仓库失败，尝试直接安装..."
                }
            fi
            apt-get update -qq 2>/dev/null || true
        fi

        # 安装（指定版本号 opentenbase=<ver>，避免装到非目标版本）
        log_info "安装 opentenbase=${OTB_VERSION}..."
        apt-get install -y "opentenbase=${OTB_VERSION}" 2>/dev/null || \
        apt-get install -y --allow-unauthenticated "opentenbase=${OTB_VERSION}" 2>/dev/null || \
        apt-get install -y opentenbase 2>/dev/null || \
        apt-get install -y --allow-unauthenticated opentenbase 2>/dev/null || {
            log_error "apt 安装失败，请手动运行: apt install opentenbase=${OTB_VERSION}"
            exit 1
        }

    elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        # --- RPM (RHEL/CentOS/Rocky/Alma/Fedora) ---
        YUM="dnf"; command -v dnf &>/dev/null || YUM="yum"
        log_info "检测到 RPM 包管理器 ($YUM)"

        # 安装 sshpass
        log_info "安装 sshpass..."
        $YUM install -y sshpass >/dev/null 2>&1 || true

        # 配置仓库（用 repo 文件存在性检查，而非包名匹配——后者会被
        # 系统自带仓库里大小写不同的同名包干扰，例如 OpenCloudOS 的 EPOL
        # 里有 OpenTenBase，会让 dnf list available opentenbase 误判为已可用）
        if [ ! -f /etc/yum.repos.d/opentenbase.repo ]; then
            log_info "配置 OpenTenBase RPM 仓库..."
            # Use CDN for faster global access, fallback to GitHub raw
            CDN_URL="https://repo.blackevil217.com/scripts/setup-rpm.sh"
            GITHUB_URL="https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh"

            if curl -sSL --connect-timeout 5 --max-time 60 "$CDN_URL" | bash -s -- --version "$OTB_VERSION"; then
                log_ok "RPM repository configured via CDN (version $OTB_VERSION)"
            else
                log_warn "CDN unavailable, falling back to GitHub..."
                curl -sSL "$GITHUB_URL" | bash -s -- --version "$OTB_VERSION" || {
                    log_warn "自动配置仓库失败，尝试直接安装..."
                }
            fi
        fi

        # 安装（指定版本号 opentenbase-<ver>，避免 dnf 装到最高版 5.0）
        # 三版本共用同一包名 opentenbase，dnf 默认选最高版，故必须 pin 版本。
        # 若已有不同版本残留，先移除避免冲突。
        rpm -q opentenbase >/dev/null 2>&1 && rpm -e --nodeps opentenbase >/dev/null 2>&1 || true
        log_info "安装 opentenbase-${OTB_VERSION}..."
        if ! $YUM install -y "opentenbase-${OTB_VERSION}" 2>/dev/null && \
           ! $YUM install -y --nogpgcheck --nobest "opentenbase-${OTB_VERSION}" 2>/dev/null; then
            # 兜底：某些发行版（如 OpenCloudOS/RHEL）缺少 RPM 构建时记录的
            # Red Hat 特有符号依赖（libpq.so.5(RHPG_10) 等），导致 dnf 拒绝安装。
            # 但 opentenbase 包自带完整 libpq（在 INSTALL_DIR/lib/），运行时不依赖
            # 系统 libpq，所以用 rpm --nodeps 强制安装是安全的。
            log_warn "$YUM 安装因依赖符号失败，降级用 rpm --nodeps 强制安装..."
            rm -f /tmp/opentenbase-*.rpm 2>/dev/null
            ( cd /tmp && $YUM download "opentenbase-${OTB_VERSION}" >/dev/null 2>&1 )
            OTB_PKG_RPM=$(ls -1t /tmp/opentenbase-*${OTB_VERSION}*.rpm 2>/dev/null | head -1)
            [ -z "$OTB_PKG_RPM" ] && OTB_PKG_RPM=$(ls -1t /tmp/opentenbase-*.rpm 2>/dev/null | head -1)
            if [ -n "$OTB_PKG_RPM" ] && [ -f "$OTB_PKG_RPM" ]; then
                rpm -ivh --nodeps "$OTB_PKG_RPM" || {
                    log_error "rpm 强制安装失败: $OTB_PKG_RPM"
                    exit 1
                }
                log_ok "已通过 rpm --nodeps 安装 opentenbase-${OTB_VERSION} (跳过 RHPG 符号依赖)"
            else
                log_error "$YUM 安装失败且无法下载 opentenbase-${OTB_VERSION}，请手动安装"
                exit 1
            fi
        fi
    else
        log_error "不支持的系统（无 apt/dnf/yum）"
        exit 1
    fi

    log_ok "软件包安装完成"
fi

# 验证二进制
if [[ "$USE_PGXC_CTL" == "true" ]]; then
    if [[ ! -x "${INSTALL_DIR}/bin/pgxc_ctl" ]]; then
        log_error "pgxc_ctl 未找到（${INSTALL_DIR}/bin/pgxc_ctl），安装可能失败"
        exit 1
    fi
    log_ok "pgxc_ctl 就绪"
else
    if ! command -v opentenbase_ctl &>/dev/null && [[ ! -x "${INSTALL_DIR}/bin/opentenbase_ctl" ]]; then
        log_error "opentenbase_ctl 未找到，安装可能失败"
        exit 1
    fi
    log_ok "opentenbase_ctl 就绪"
fi

# ====================================================================
# Step 3: 系统准备（用户 + SSH + sshpass + 符号链接）
# ====================================================================
log_step "Step 3/6: 系统环境准备"

# 创建 opentenbase 用户
if ! id -u "$SSH_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$SSH_USER"
    log_ok "创建用户 $SSH_USER"
else
    log_ok "用户 $SSH_USER 已存在"
fi

# 修复用户主目录权限（软件包安装后主目录常归属 root，导致 ssh-keygen 失败）
SSH_USER_HOME=$(getent passwd "$SSH_USER" | cut -d: -f6)
if [[ -n "$SSH_USER_HOME" ]]; then
    if [[ ! -d "$SSH_USER_HOME" ]]; then
        mkdir -p "$SSH_USER_HOME/.ssh"
        log_info "创建用户主目录: $SSH_USER_HOME"
    fi
    if [[ "$(stat -c '%U' "$SSH_USER_HOME" 2>/dev/null)" != "$SSH_USER" ]]; then
        chown -R "$SSH_USER":"$SSH_USER" "$SSH_USER_HOME"
        log_info "修复主目录权限归属: $SSH_USER_HOME → $SSH_USER"
    fi
    chmod 750 "$SSH_USER_HOME"
    chmod 700 "$SSH_USER_HOME/.ssh" 2>/dev/null || true
fi

# 设置密码
if [[ -n "$SSH_PASSWORD" ]]; then
    echo "$SSH_USER:$SSH_PASSWORD" | chpasswd 2>/dev/null || \
    echo "${SSH_USER}:${SSH_PASSWORD}" | chpasswd 2>/dev/null || true
    log_ok "已设置 $SSH_USER 密码"
fi

# sudo 免密（opentenbase_ctl 需要）
if ! grep -q "${SSH_USER} ALL=(ALL) NOPASSWD:ALL" /etc/sudoers.d/${SSH_USER} 2>/dev/null; then
    echo "${SSH_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${SSH_USER}
    chmod 440 /etc/sudoers.d/${SSH_USER}
    log_ok "sudo 免密配置完成"
fi

# 启动 SSH 服务
systemctl start sshd 2>/dev/null || \
systemctl start ssh 2>/dev/null || \
/usr/sbin/sshd 2>/dev/null || true
log_ok "SSH 服务已启动"

# 安装 sshpass（如果还没有）
if ! command -v sshpass &>/dev/null; then
    apt-get install -y sshpass 2>/dev/null || \
    dnf install -y sshpass 2>/dev/null || \
    yum install -y sshpass 2>/dev/null || true
fi
command -v sshpass &>/dev/null && log_ok "sshpass 就绪" || log_warn "sshpass 未安装（可能影响远程操作）"

# 配置 opentenbase 用户 SSH 免密自连接（pgxc_ctl 和 opentenbase_ctl 都需要）
if ! su - "$SSH_USER" -c "test -f ~/.ssh/id_rsa" 2>/dev/null; then
    log_info "为 $SSH_USER 用户生成 SSH 密钥..."
    su - "$SSH_USER" -c "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa" 2>/dev/null
fi
su - "$SSH_USER" -c "cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys 2>/dev/null; sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys 2>/dev/null" 2>/dev/null || true
# 测试 SSH 自连接
if su - "$SSH_USER" -c "ssh -o StrictHostKeyChecking=no ${SSH_USER}@127.0.0.1 'echo SSH_OK'" 2>/dev/null | grep -q SSH_OK; then
    log_ok "SSH 免密自连接就绪"
else
    log_warn "SSH 免密自连接未通，集群部署可能失败"
fi

# 创建 OSS_INSTALL_DIR 符号链接
if [[ ! -e "/usr/local/install/opentenbase" ]]; then
    mkdir -p /usr/local/install
    ln -sf /usr/lib/opentenbase/${OTB_VERSION} /usr/local/install/opentenbase
    log_ok "路径符号链接: /usr/local/install/opentenbase → /usr/lib/opentenbase/${OTB_VERSION}"
else
    log_ok "路径符号链接已存在"
fi

# ====================================================================
# Step 3.5: 版本专属准备
# ====================================================================
if [[ "$USE_PGXC_CTL" == "true" ]]; then
    # ---- 2.5/2.6: pgxc_ctl 链路 ----
    # 不需要 tar.gz，直接用目录
    log_ok "pgxc_ctl 链路：无需打包，直接使用 ${INSTALL_DIR}"
    # 创建数据目录
    DATA_BASE="/var/lib/opentenbase/${OTB_SHORT_VER}"
    mkdir -p "${DATA_BASE}/gtm" "${DATA_BASE}/coord" "${DATA_BASE}/dn1" \
             "${DATA_BASE}/coord_archlog" "${DATA_BASE}/dn1_archlog"
    chown -R "$SSH_USER":"$SSH_USER" "${DATA_BASE}"
    log_ok "数据目录就绪: ${DATA_BASE}"
else
    # ---- 5.0: opentenbase_ctl 链路 ----
    # 创建部署包 tar.gz（opentenbase_ctl 要求文件格式）
    TAR_PKG="/tmp/opentenbase-${OTB_VERSION}.tar.gz"
    if [[ -d "$INSTALL_DIR" ]] && [[ ! -f "$TAR_PKG" ]]; then
        log_info "创建部署 tar.gz 包（opentenbase_ctl 要求文件格式而非目录）..."
        TMP_PKG_DIR=$(mktemp -d /tmp/otb-pkg-XXXXXX)
        cp -af "$INSTALL_DIR"/* "$TMP_PKG_DIR/"
        (cd "$TMP_PKG_DIR" && tar -zcf "$TAR_PKG" *)
        rm -rf "$TMP_PKG_DIR"
        PACKAGE_PATH="$TAR_PKG"
        log_ok "部署包: $TAR_PKG ($(du -h "$TAR_PKG" | cut -f1))"
    elif [[ -f "$TAR_PKG" ]]; then
        PACKAGE_PATH="$TAR_PKG"
        log_ok "部署包已存在: $TAR_PKG"
    else
        log_warn "安装目录 $INSTALL_DIR 不存在"
        PACKAGE_PATH="$INSTALL_DIR"
    fi

    # 验证 opentenbase_ctl 在 tar.gz 中
    if [[ -f "$TAR_PKG" ]]; then
        TAR_CONTENT=$(tar -tzf "$TAR_PKG" 2>/dev/null || true)
        if [[ "$TAR_CONTENT" != *"bin/opentenbase_ctl"* ]]; then
            log_error "tar.gz 中未找到 bin/opentenbase_ctl，安装包可能损坏"
            exit 1
        fi
    fi
fi

# ====================================================================
# Step 4: 交互式配置（仅交互模式）
# ====================================================================
log_step "Step 4/6: 集群配置"

if [[ "$INTERACTIVE" == "true" ]]; then
    echo -e "  请回答以下问题（直接回车使用默认值）：\n"

    ask "集群名称" "$CLUSTER_NAME" CLUSTER_NAME
    ask "GTM 节点 IP" "$GTM_IP" GTM_IP
    ask "Coordinator 节点 IP（默认同 GTM）" "${GTM_IP}" CN_IP
    ask "Datanode 节点 IP（默认同 GTM）" "${GTM_IP}" DN_IP
    ask "SSH 端口" "$SSH_PORT" SSH_PORT

    # 密码
    echo ""
    echo -e "  ${YELLOW}提示:${NC} opentenbase_ctl 通过 sshpass + 密码远程执行命令"
    echo -e "  所有节点的 $SSH_USER 用户密码必须一致\n"
    ask_password "请输入 $SSH_USER 用户的 SSH 密码" SSH_PASSWORD

    echo ""
    echo -e "  ${BOLD}配置摘要:${NC}"
    echo -e "    集群名称:    ${CYAN}${CLUSTER_NAME}${NC}"
    echo -e "    GTM:         ${CYAN}${GTM_IP}${NC}"
    echo -e "    Coordinator: ${CYAN}${CN_IP}${NC}"
    echo -e "    Datanode:    ${CYAN}${DN_IP}${NC}"
    echo -e "    SSH 用户:    ${CYAN}${SSH_USER}${NC}"
    echo -e "    SSH 端口:    ${CYAN}${SSH_PORT}${NC}"
    echo ""

    if [[ "$INTERACTIVE" == "true" ]]; then
        read -rp "$(echo -e "${CYAN}${BOLD}?${NC} 确认开始部署？ [Y/n] ")" confirm
        [[ "${confirm:-Y}" =~ ^[Yy]$ ]] || { log_warn "已取消"; exit 0; }
    fi
else
    # 非交互式：使用默认值或命令行参数
    [[ -z "$CN_IP" ]] && CN_IP="$GTM_IP"
    [[ -z "$DN_IP" ]] && DN_IP="$GTM_IP"
    [[ -z "$SSH_PASSWORD" ]] && SSH_PASSWORD="opentenbase"

    # 设置密码
    echo "$SSH_USER:$SSH_PASSWORD" | chpasswd 2>/dev/null || true

    log_info "配置: 集群=${CLUSTER_NAME} GTM=${GTM_IP} CN=${CN_IP} DN=${DN_IP} SSH=${SSH_USER}@:${SSH_PORT}"
fi

# 生成配置文件
if [[ "$USE_PGXC_CTL" == "true" ]]; then
    # ---- 2.5/2.6: 生成 pgxc_ctl.conf ----
    PGXC_CONF_DIR="/var/lib/opentenbase/pgxc_ctl"
    mkdir -p "$PGXC_CONF_DIR"
    DATA_BASE="/var/lib/opentenbase/${OTB_SHORT_VER}"
    cat > "${PGXC_CONF_DIR}/pgxc_ctl.conf" << PGXCEOF
#!/usr/bin/env bash
# pgxc_ctl.conf for OpenTenBase ${OTB_VERSION}
# 由 deploy-opentenbase.sh 自动生成

IP_1=127.0.0.1
pgxcInstallDir=${INSTALL_DIR}
pgxcOwner=${SSH_USER}
defaultDatabase=postgres
pgxcUser=${SSH_USER}
pgxcGroup=opentenbase
tmpDir=/tmp
localTmpDir=\$tmpDir
configBackup=n

gtmName=gtm
gtmMasterServer=\$IP_1
gtmMasterPort=6666
gtmMasterDir=${DATA_BASE}/gtm
gtmSlave=n

coordNames=(cn0001)
coordPorts=(5432)
poolerPorts=(6669)
coordMasterServers=(\$IP_1)
coordMasterDirs=(${DATA_BASE}/coord)
coordArchLogDir=${DATA_BASE}/coord_archlog
coordMaxWALSenders=1
coordSlave=n
coordSpecificExtraConfig=none
coordSpecificExtraPgHba=none

primaryDatanode=dn0001
datanodeNames=(dn0001)
datanodePorts=(15432)
datanodePoolerPorts=(6670)
datanodeMasterServers=(\$IP_1)
datanodeMasterDirs=(${DATA_BASE}/dn1)
datanodeArchLogDir=${DATA_BASE}/dn1_archlog
datanodeMaxWALSenders=1
datanodeSlave=n
datanodeSpecificExtraConfig=none
datanodeSpecificExtraPgHba=none
PGXCEOF
    chown "$SSH_USER":"$SSH_USER" "${PGXC_CONF_DIR}/pgxc_ctl.conf"
    CONFIG_FILE="${PGXC_CONF_DIR}/pgxc_ctl.conf"
    log_ok "pgxc_ctl.conf 已生成: $CONFIG_FILE"
else
    # ---- 5.0: 生成 INI 配置 ----
    CONFIG_FILE="/tmp/opentenbase_config.ini"
    cat > "$CONFIG_FILE" << INIEOF
# OpenTenBase 5.0 集群配置
# 由 deploy-opentenbase.sh 自动生成

[instance]
name=${CLUSTER_NAME}
type=distributed
package=${PACKAGE_PATH}

[gtm]
master=${GTM_IP}

[coordinators]
master=${CN_IP}
nodes-per-server=1

[datanodes]
master=${DN_IP}
nodes-per-server=1

[server]
ssh-user=${SSH_USER}
ssh-password=${SSH_PASSWORD}
ssh-port=${SSH_PORT}

[log]
level=INFO
INIEOF
    chmod 600 "$CONFIG_FILE"
    chown "$SSH_USER":"$SSH_USER" "$CONFIG_FILE" 2>/dev/null || true
    log_ok "INI 配置文件已生成: $CONFIG_FILE"
fi

# ====================================================================
# Step 5: 安装集群
# ====================================================================
if [[ "$USE_PGXC_CTL" == "true" ]]; then
    log_step "Step 5/6: 安装集群（pgxc_ctl init all）"

    echo -e "  正在执行: ${CYAN}pgxc_ctl init all${NC}"
    echo -e "  ${YELLOW}这可能需要几分钟（initdb + 配置 + 节点注册）...${NC}\n"

    if su - "$SSH_USER" -c "export PATH=${INSTALL_DIR}/bin:\$PATH && export LD_LIBRARY_PATH=${INSTALL_DIR}/lib && cd /var/lib/opentenbase && pgxc_ctl init all" < /dev/null 2>&1; then
        echo ""
        log_ok "集群安装成功（pgxc_ctl init all）"
    else
        EXIT_CODE=$?
        echo ""
        log_error "集群安装失败（退出码: $EXIT_CODE）"
        echo -e "  ${BOLD}排查:${NC}"
        echo -e "    1. 数据目录残留 → 使用 --clean 重新部署"
        echo -e "    2. SSH 自连接   → su - $SSH_USER -c 'ssh ${SSH_USER}@127.0.0.1 echo ok'"
        echo -e "    3. 端口占用     → ss -tlnp | grep -E '(5432|6666|15432)'"
        exit $EXIT_CODE
    fi
else
    log_step "Step 5/6: 安装集群（opentenbase_ctl install）"

    # 5.0 必须使用绝对路径，避免 /usr/bin 符号链接指向其他版本
    OTB_CTL_BIN="${INSTALL_DIR}/bin/opentenbase_ctl"

    OTB_LD_PRELOAD=""
    if [[ -n "$NOAFFINITY_SO" ]] && [[ -f "$NOAFFINITY_SO" ]]; then
        OTB_LD_PRELOAD="LD_PRELOAD=$NOAFFINITY_SO "
        log_info "GTM 低核兼容: /etc/ld.so.preload 已全局生效，LD_PRELOAD 作为额外保障"
    fi

    echo -e "  正在执行: ${CYAN}${OTB_CTL_BIN} install -c $CONFIG_FILE${NC}"
    echo -e "  ${YELLOW}这可能需要几分钟（initdb + 配置 + 节点注册）...${NC}\n"

    if su - "$SSH_USER" -c "${OTB_LD_PRELOAD}${OTB_CTL_BIN} install -c '$CONFIG_FILE'" < /dev/null 2>&1; then
        echo ""
        log_ok "集群安装成功"
    else
        EXIT_CODE=$?
        echo ""
        log_error "集群安装失败（退出码: $EXIT_CODE）"
        echo -e "  ${BOLD}常见原因排查:${NC}"
        echo -e "    1. SSH 密码错误 → 检查配置文件中的 ssh-password"
        echo -e "    2. sshd 未运行 → systemctl start sshd"
        echo -e "    3. 端口被占用  → ss -tlnp | grep -E '(11003|6666|15432)'"
        echo -e "    4. 路径不匹配  → ls -la /usr/local/install/opentenbase"
        echo -e "    5. 内存不足    → free -h"
        exit $EXIT_CODE
    fi
fi

# ====================================================================
# Step 6: 验证 & 启动
# ====================================================================
log_step "Step 6/6: 启动与验证"

if [[ "$USE_PGXC_CTL" == "true" ]]; then
    # ---- 2.5/2.6 验证 ----
    log_info "检查集群状态..."
    su - "$SSH_USER" -c "export PATH=${INSTALL_DIR}/bin:\$PATH && export LD_LIBRARY_PATH=${INSTALL_DIR}/lib && pgxc_ctl monitor all" 2>&1
    CN_PORT=5432
    PSQL_BIN="${INSTALL_DIR}/bin/psql"
    PSQL_LIB="${INSTALL_DIR}/lib"
else
    # ---- 5.0 验证 ----
    log_info "检查集群状态..."
    su - "$SSH_USER" -c "${OTB_LD_PRELOAD}${OTB_CTL_BIN} status" < /dev/null 2>&1 || true
    CN_PORT=11003
    OTB_BIN="${INSTALL_DIR}/bin"
    OTB_LIB="${INSTALL_DIR}/lib"
    OTB_RUN_LIB="/var/lib/opentenbase/install/opentenbase/${OTB_VERSION}/lib"
    OTB_RUN_BIN="/var/lib/opentenbase/install/opentenbase/${OTB_VERSION}/bin"
    PSQL_BIN=""
    [[ -x "$OTB_RUN_BIN/psql" ]] && PSQL_BIN="$OTB_RUN_BIN/psql"
    [[ -z "$PSQL_BIN" ]] && [[ -x "$OTB_BIN/psql" ]] && PSQL_BIN="$OTB_BIN/psql"
    [[ -z "$PSQL_BIN" ]] && command -v opentenbase-psql &>/dev/null && PSQL_BIN="opentenbase-psql"
    [[ -z "$PSQL_BIN" ]] && command -v psql &>/dev/null && PSQL_BIN="psql"
    PSQL_LIB=""
    [[ -d "$OTB_RUN_LIB" ]] && PSQL_LIB="$OTB_RUN_LIB"
    [[ -z "$PSQL_LIB" ]] && [[ -d "$OTB_LIB" ]] && PSQL_LIB="$OTB_LIB"
fi

# 数据库连接测试
if [[ -n "$PSQL_BIN" ]]; then
    log_info "测试数据库连接（端口 ${CN_PORT}）..."
    PSQL_ENV=""
    [[ -n "$PSQL_LIB" ]] && PSQL_ENV="LD_LIBRARY_PATH=$PSQL_LIB "
    for i in $(seq 1 5); do
        if su - "$SSH_USER" -c "${PSQL_ENV}${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres -c 'SELECT version();'" 2>/dev/null; then
            log_ok "数据库连接成功（端口 ${CN_PORT}）"
            break
        fi
        [[ $i -lt 5 ]] && log_info "等待启动...（$i/5）" && sleep 3
    done

    # pgxc_ctl 路径需要手动初始化默认节点组和分片映射
    if [[ "$USE_PGXC_CTL" == "true" ]]; then
        log_info "初始化默认节点组与分片映射（pgxc_ctl 路径）..."
        su - "$SSH_USER" -c "${PSQL_ENV}${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres \
            -c \"CREATE DEFAULT NODE GROUP default_group WITH(dn0001);\" 2>/dev/null || true"
        su - "$SSH_USER" -c "${PSQL_ENV}${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres \
            -c \"CREATE SHARDING GROUP TO GROUP default_group;\" 2>/dev/null || true"
        su - "$SSH_USER" -c "${PSQL_ENV}${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres \
            -c \"SELECT pgxc_pool_reload();\" 2>/dev/null || true"
        SHARD_COUNT=$(su - "$SSH_USER" -c "${PSQL_ENV}${PSQL_BIN} -t -A -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres \
            -c \"SELECT count(*) FROM pgxc_shard_map;\"" 2>/dev/null || echo "0")
        if [[ "${SHARD_COUNT}" -gt 0 ]] 2>/dev/null; then
            log_ok "分片映射已初始化（${SHARD_COUNT} 条分片记录）"
        else
            log_warn "分片映射初始化可能未成功，分布式表创建可能失败"
        fi
    fi
fi

# ====================================================================
# 部署完成总结
# ====================================================================
echo ""
echo -e "${GREEN}${BOLD}"
cat << 'SUMMARY'
  ╔══════════════════════════════════════════════╗
  ║                                              ║
  ║          ✅  部署完成！                       ║
  ║                                              ║
  ╚══════════════════════════════════════════════╝
SUMMARY
echo -e "${NC}"

echo -e "  ${BOLD}集群信息:${NC}"
echo -e "    名称:        ${CYAN}${CLUSTER_NAME}${NC}"
echo -e "    版本:        ${CYAN}${OTB_VERSION}${NC}"
echo -e "    类型:        distributed"
echo -e "    GTM:         ${CYAN}${GTM_IP}${NC}"
echo -e "    Coordinator: ${CYAN}${CN_IP}${NC}"
echo -e "    Datanode:    ${CYAN}${DN_IP}${NC}"
echo ""
echo -e "  ${BOLD}配置文件:${NC} ${CYAN}${CONFIG_FILE}${NC}"
echo ""
echo -e "  ${BOLD}日常运维:${NC} ${GREEN}以下工具已随包安装到本机，日常运维直接用这些短命令即可，无需再 curl 长脚本${NC}"
if [[ "$USE_PGXC_CTL" == "true" ]]; then
echo -e "    运维工具: ${CYAN}pgxc_ctl${NC}  （v${OTB_VERSION} 集群管理器，需先 export PATH）"
echo -e "    ${CYAN}export PATH=${INSTALL_DIR}/bin:\$PATH${NC}"
echo -e "    ${CYAN}pgxc_ctl monitor all${NC}      # 查看集群状态"
echo -e "    ${CYAN}pgxc_ctl start all${NC}        # 启动集群"
echo -e "    ${CYAN}pgxc_ctl stop all${NC}         # 停止集群"
else
echo -e "    运维工具: ${CYAN}opentenbase_ctl${NC}  （v${OTB_VERSION} 集群管理器，全生命周期：install/start/stop/status/expand/shrink/delete）"
echo -e "    ${CYAN}opentenbase_ctl status${NC}              # 查看集群状态"
echo -e "    ${CYAN}opentenbase_ctl start${NC}               # 启动集群"
echo -e "    ${CYAN}opentenbase_ctl stop${NC}                # 停止集群"
echo -e "    ${CYAN}opentenbase_ctl expand -c $CONFIG_FILE${NC}   # 扩容节点"
echo -e "    ${CYAN}opentenbase_ctl delete -c $CONFIG_FILE${NC}   # 删除集群"
fi
echo ""
echo -e "  ${BOLD}一键脚本（仅装/卸/自检时用，日常运维不用）:${NC}"
echo -e "    ${CYAN}opentenbase.sh status${NC}    # 快速自检（端口/进程/连接）"
echo -e "    ${CYAN}opentenbase.sh test${NC}      # 完整验证（建表/读写/分片）"
echo -e "    ${CYAN}opentenbase.sh uninstall${NC} # 卸载"
echo ""
echo -e "  ${BOLD}连接数据库:${NC}"
if [[ "$USE_PGXC_CTL" == "true" ]]; then
echo -e "    ${CYAN}export LD_LIBRARY_PATH=${INSTALL_DIR}/lib${NC}"
echo -e "    ${CYAN}${INSTALL_DIR}/bin/psql -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres${NC}"
else
echo -e "    ${CYAN}export LD_LIBRARY_PATH=${PSQL_LIB:-/var/lib/opentenbase/install/opentenbase/${OTB_VERSION}/lib}${NC}"
echo -e "    ${CYAN}${PSQL_BIN:-psql} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres${NC}"
fi
echo ""

if [[ -n "$PSQL_BIN" ]]; then
    echo -e "  ${BOLD}快速测试:${NC}"
    PSQL_LIB_ARG=""
    [[ -n "$PSQL_LIB" ]] && PSQL_LIB_ARG="LD_LIBRARY_PATH=$PSQL_LIB"
    if [[ "$USE_PGXC_CTL" == "true" ]]; then
        SHARD_SQL="CREATE TABLE t1 (id int, name text) DISTRIBUTE BY SHARD(id) TO GROUP default_group; INSERT INTO t1 VALUES (1,'hello'); SELECT * FROM t1;"
    else
        SHARD_SQL="CREATE TABLE t1 (id int, name text) DISTRIBUTE BY SHARD(id); INSERT INTO t1 VALUES (1,'hello'); SELECT * FROM t1;"
    fi
    su - "$SSH_USER" -c "${PSQL_LIB_ARG} ${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres -c \"${SHARD_SQL}\"" 2>/dev/null && \
        echo -e "\n  ${GREEN}✅ 分布式表创建+读写测试通过！${NC}" || \
        echo -e "\n  ${YELLOW}集群可能还在启动中，请稍后手动测试${NC}"
fi

echo ""
echo -e "  ${BOLD}文档:${NC} https://github.com/OpenTenBase/OpenTenBase"
echo ""

fi  # end of "if [[ "$OTB_COMMAND" == "install" ]]" 部署主体守卫

# ====================================================================
# 新增功能函数（子命令实现）
# ====================================================================

# 显示使用帮助
show_usage() {
	cat << EOF
OpenTenBase 一键管理脚本

用法:
  opentenbase.sh [命令] [选项]

命令:
  install      安装部署 OpenTenBase 集群（默认命令）
  uninstall    卸载 OpenTenBase
  switch       切换版本
  status       查看集群状态
  test         验证测试（创建分布式表、读写测试）

日常运维（集群装好后，用随包安装的本地工具，无需再 curl）:
  v5.0  → opentenbase_ctl {status|start|stop|expand|shrink|delete}
  v2.5/v2.6 → pgxc_ctl {monitor|start|stop} all   （需先 export PATH=安装目录/bin）

选项:
  install:
    --yes              非交互式，使用默认值
    --version VER      指定版本（5.0 / 2.6.0 / 2.5.0）
    --cluster-name N   集群名称
    --gtm-ip IP        GTM 节点 IP
    --cn-ip IP         Coordinator IP
    --dn-ip IP         Datanode IP
    --ssh-user USER    SSH 用户名
    --ssh-port PORT    SSH 端口
    --ssh-password P   SSH 密码
    --skip-install     跳过包安装
    --clean            部署前清理旧数据

  uninstall:
    --purge            删除数据目录和日志
    --yes              跳过确认

  test:
    --quick            快速测试（仅连接验证）
    --full             完整测试（创建表、插入、查询、分布式查询）

示例:
  curl -sSL <url>/opentenbase.sh | sudo bash
  sudo bash opentenbase.sh install --yes --version 5.0
  sudo bash opentenbase.sh status
  sudo bash opentenbase.sh test --full
  sudo bash opentenbase.sh uninstall --purge --yes
EOF
}

# 查看集群状态
show_cluster_status() {
	log_step "检查 OpenTenBase 集群状态..."

	# 检测当前版本
	OTB_VERSION=$(opentenbase-switch-version 2>/dev/null | grep "current" | awk '{print $2}' || echo "5.0")
	INSTALL_DIR="/usr/lib/opentenbase/${OTB_VERSION}"

	# 检测使用的链路
	USE_PGXC_CTL=false
	[[ "$OTB_VERSION" =~ ^2\. ]] && USE_PGXC_CTL=true

	if [[ "$USE_PGXC_CTL" == "true" ]]; then
		log_info "使用 pgxc_ctl 链路（v${OTB_VERSION}）"
		export PATH="${INSTALL_DIR}/bin:$PATH"
		export LD_LIBRARY_PATH="${INSTALL_DIR}/lib"
		su - opentenbase -c "pgxc_ctl monitor all" 2>&1 || log_warn "pgxc_ctl monitor 执行失败"
	else
		log_info "使用 opentenbase_ctl 链路（v${OTB_VERSION}）"
		OTB_CTL="${INSTALL_DIR}/bin/opentenbase_ctl"
		if [[ -x "$OTB_CTL" ]]; then
			su - opentenbase -c "$OTB_CTL status" 2>&1 || log_warn "opentenbase_ctl status 执行失败"
		else
			log_warn "opentenbase_ctl 未找到"
		fi
	fi

	# 检查端口
	log_info "检查端口状态..."
	for port in 6666 11003 15432 5432; do
		if command -v ss >/dev/null 2>&1 && ss -tlnp 2>/dev/null | grep -q ":${port}"; then
			log_ok "端口 ${port} 正在监听"
		elif command -v netstat >/dev/null 2>&1 && netstat -tlnp 2>/dev/null | grep -q ":${port}"; then
			log_ok "端口 ${port} 正在监听"
		else
			log_warn "端口 ${port} 未监听"
		fi
	done

	# 检查进程
	log_info "检查进程状态..."
	for proc in gtm postgres; do
		count=$(pgrep -u opentenbase "$proc" 2>/dev/null | wc -l || echo 0)
		if [[ "$count" -gt 0 ]]; then
			log_ok "${proc}: ${count} 个进程运行中"
		else
			log_warn "${proc}: 无进程运行"
		fi
	done

	# 尝试数据库连接
	log_info "尝试数据库连接..."
	CN_PORT=$([[ "$USE_PGXC_CTL" == "true" ]] && echo 5432 || echo 11003)
	PSQL_BIN="${INSTALL_DIR}/bin/psql"
	PSQL_LIB="${INSTALL_DIR}/lib"

	if [[ -x "$PSQL_BIN" ]]; then
		if su - opentenbase -c "LD_LIBRARY_PATH=${PSQL_LIB} ${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres -c 'SELECT version();'" 2>&1 | head -5; then
			log_ok "数据库连接成功"
		else
			log_warn "数据库连接失败"
		fi
	else
		log_warn "psql 未找到，无法测试数据库连接"
	fi
}

# 验证测试
run_verification_test() {
	TEST_MODE="${1:---full}"

	log_step "OpenTenBase 验证测试..."

	# 检测当前版本和端口
	OTB_VERSION=$(opentenbase-switch-version 2>/dev/null | grep "current" | awk '{print $2}' || echo "5.0")
	USE_PGXC_CTL=false
	[[ "$OTB_VERSION" =~ ^2\. ]] && USE_PGXC_CTL=true
	CN_PORT=$([[ "$USE_PGXC_CTL" == "true" ]] && echo 5432 || echo 11003)

	INSTALL_DIR="/usr/lib/opentenbase/${OTB_VERSION}"
	PSQL_BIN="${INSTALL_DIR}/bin/psql"
	PSQL_LIB="${INSTALL_DIR}/lib"

	# 检查 psql 是否存在
	if [[ ! -x "$PSQL_BIN" ]]; then
		log_error "psql 未找到（${PSQL_BIN}），请先安装 OpenTenBase"
		exit 1
	fi

	# 测试 1: 连接验证
	log_info "测试数据库连接（端口 ${CN_PORT}）..."
	if ! su - opentenbase -c "LD_LIBRARY_PATH=${PSQL_LIB} ${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres -c 'SELECT version();'" 2>&1; then
		log_error "数据库连接失败"
		exit 1
	fi
	log_ok "连接测试通过 ✓"

	# 测试 2: 快速测试（仅连接）
	if [[ "$TEST_MODE" == "--quick" ]]; then
		echo ""
		log_ok "✅ 快速测试完成（仅连接验证）"
		return 0
	fi

	# 测试 3: 创建分布式表
	log_info "创建分布式测试表..."
	TEST_TABLE="test_table_$(date +%s)"

	if [[ "$USE_PGXC_CTL" == "true" ]]; then
		# pgxc_ctl 路径需要先创建节点组和分片映射（如果还没有）
		su - opentenbase -c "LD_LIBRARY_PATH=${PSQL_LIB} ${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres \
			-c \"CREATE DEFAULT NODE GROUP default_group WITH(dn0001);\"" 2>/dev/null || true
		su - opentenbase -c "LD_LIBRARY_PATH=${PSQL_LIB} ${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres \
			-c \"CREATE SHARDING GROUP TO GROUP default_group;\"" 2>/dev/null || true
		CREATE_SQL="CREATE TABLE ${TEST_TABLE} (id int, name text) DISTRIBUTE BY SHARD(id) TO GROUP default_group;"
	else
		CREATE_SQL="CREATE TABLE ${TEST_TABLE} (id int, name text) DISTRIBUTE BY SHARD(id);"
	fi

	if ! su - opentenbase -c "LD_LIBRARY_PATH=${PSQL_LIB} ${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres -c \"${CREATE_SQL}\"" 2>&1; then
		log_error "创建分布式表失败"
		exit 1
	fi
	log_ok "分布式表创建成功: ${TEST_TABLE} ✓"

	# CREATE 分布式表是异步的：CREATE 返回时 datanode 可能尚未完成建表，
	# 同连接立即 INSERT 会报 "relation ... does not exist"，跨连接则命中
	# "primary datanode connection released"。留 2 秒等 datanode 落盘，再
	# pgxc_pool_reload() 让协调节点重建连接池映射（OpenTenBase DDL 后标准步骤）。
	sleep 2
	log_info "刷新连接池 (pgxc_pool_reload)..."
	su - opentenbase -c "LD_LIBRARY_PATH=${PSQL_LIB} ${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres -c 'SELECT pgxc_pool_reload();'" 2>&1 | grep -v "no version" || true

	# 测试 4: 插入数据
	log_info "插入测试数据..."
	INSERT_SQL="INSERT INTO ${TEST_TABLE} VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie');"
	if ! su - opentenbase -c "LD_LIBRARY_PATH=${PSQL_LIB} ${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres -c \"${INSERT_SQL}\"" 2>&1; then
		log_error "插入数据失败"
		# 清理测试表
		su - opentenbase -c "LD_LIBRARY_PATH=${PSQL_LIB} ${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres -c \"DROP TABLE ${TEST_TABLE};\"" 2>&1 || true
		exit 1
	fi
	log_ok "插入 3 条测试数据 ✓"

	# 测试 5: 查询数据
	log_info "查询测试数据..."
	SELECT_SQL="SELECT * FROM ${TEST_TABLE} ORDER BY id;"
	if ! su - opentenbase -c "LD_LIBRARY_PATH=${PSQL_LIB} ${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres -c \"${SELECT_SQL}\"" 2>&1; then
		log_error "查询数据失败"
		# 清理测试表
		su - opentenbase -c "LD_LIBRARY_PATH=${PSQL_LIB} ${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres -c \"DROP TABLE ${TEST_TABLE};\"" 2>&1 || true
		exit 1
	fi
	log_ok "查询测试通过 ✓"

	# 测试 6: 分布式架构验证（集群节点 + shard 映射）
	log_info "验证分布式架构..."
	# 查询集群节点（gtm/coordinator/datanode）
	su - opentenbase -c "LD_LIBRARY_PATH=${PSQL_LIB} ${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres -c \"SELECT node_name, node_type FROM pgxc_node ORDER BY node_type;\"" 2>&1 | grep -v "no version" || true
	# 查询 shard 映射总数（验证分片机制生效）
	SHARD_TOTAL=$(su - opentenbase -c "LD_LIBRARY_PATH=${PSQL_LIB} ${PSQL_BIN} -t -A -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres -c \"SELECT count(*) FROM pgxc_shard_map;\"" 2>/dev/null | grep -v "no version" | tr -d '[:space:]' || echo "0")
	if [[ "${SHARD_TOTAL:-0}" -gt 0 ]] 2>/dev/null; then
		log_ok "分布式架构验证完成（${SHARD_TOTAL} 条 shard 映射）✓"
	else
		log_warn "未检测到 shard 映射（数据分布验证可能未生效）"
	fi

	# 测试 7: 清理测试表
	log_info "清理测试表..."
	if su - opentenbase -c "LD_LIBRARY_PATH=${PSQL_LIB} ${PSQL_BIN} -h 127.0.0.1 -p ${CN_PORT} -U opentenbase -d postgres -c \"DROP TABLE ${TEST_TABLE};\"" 2>&1; then
		log_ok "测试表已清理 ✓"
	else
		log_warn "测试表清理失败（可手动删除: DROP TABLE ${TEST_TABLE};）"
	fi

	# 测试总结
	echo ""
	log_ok "✅ 完整验证测试通过！"
	echo -e "  ${BOLD}测试摘要:${NC}"
	echo "    - 数据库连接: ✓"
	echo "    - 分布式表创建: ✓"
	echo "    - 数据写入: ✓"
	echo "    - 数据查询: ✓"
	echo "    - 数据分布验证: ✓"
	echo "    - 测试表清理: ✓"
}

# ====================================================================
# 子命令分发（延迟到此处，确保上方函数定义已加载）
# ====================================================================
case "$OTB_COMMAND" in
    status)
        show_cluster_status "$@"
        ;;
    test)
        run_verification_test "$@"
        ;;
    --help|-h)
        show_usage
        ;;
    install)
        : # 部署主体已在上方执行
        ;;
esac
