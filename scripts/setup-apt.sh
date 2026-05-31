#!/bin/bash
# OpenTenBase APT 仓库一键安装脚本
# Usage: curl -sSL https://github.com/muzimu217/OpenTenBase-deb/releases/latest/download/setup-apt.sh | sudo bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 配置 - Auto-detect fastest mirror
detect_mirror() {
    local cf_url="https://apt.blackevil217.com/apt"
    local gitee_url="https://blackEvil217.gitee.io/opentenbase-packages/apt"
    local github_url="https://muzimu217.github.io/OpenTenBase-deb/apt"

    # Try Cloudflare CDN first (global acceleration)
    if curl -sLf --connect-timeout 5 --max-time 10 "${cf_url}/gpg-key.asc" -o /dev/null 2>/dev/null; then
        APT_REPO_URL="$cf_url"
        log_info "Using Cloudflare CDN mirror (apt.blackevil217.com)"
    # Try Gitee second (faster in China)
    elif curl -sLf --connect-timeout 5 --max-time 10 "${gitee_url}/gpg-key.asc" -o /dev/null 2>/dev/null; then
        APT_REPO_URL="$gitee_url"
        log_info "Using Gitee mirror (faster in China)"
    else
        APT_REPO_URL="$github_url"
        log_info "Using GitHub repository"
    fi
}

# Fallback: try both mirrors for a given path
fetch_from_mirror() {
    local path=$1
    local url="${APT_REPO_URL}${path}"
    local result
    result=$(curl -sL --connect-timeout 10 --max-time 30 "$url" 2>/dev/null)
    if [ -n "$result" ] && ! echo "$result" | grep -q "404"; then
        echo "$result"
        return 0
    fi
    # Fallback to GitHub
    local github_url="https://muzimu217.github.io/OpenTenBase-deb/apt${path}"
    result=$(curl -sL --connect-timeout 10 --max-time 30 "$github_url" 2>/dev/null)
    if [ -n "$result" ] && ! echo "$result" | grep -q "404"; then
        echo "$result"
        return 0
    fi
    return 1
}

detect_mirror
REPO_URL="https://github.com/muzimu217/OpenTenBase-deb/releases/latest/download"
GPG_KEY_URL="${APT_REPO_URL}/gpg-key.asc"
KEYRING_PATH="/usr/share/keyrings/opentenbase-archive-keyring.gpg"
SOURCES_LIST="/etc/apt/sources.list.d/opentenbase.list"
# Pinned signing-key fingerprint. The downloaded key is verified against this
# value so a compromised mirror cannot substitute a different key (TOFU -> pin).
EXPECTED_FINGERPRINT="D8B2E316E1FF88EE178703549D8FA46F3A55D5F0"

# Verify that an (armored) GPG key file matches the pinned fingerprint.
verify_key_fingerprint() {
    local keyfile="$1"
    local got
    got=$(gpg --show-keys --with-colons "$keyfile" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')
    if [ "$got" != "$EXPECTED_FINGERPRINT" ]; then
        log_error "GPG 密钥指纹不匹配，已拒绝该密钥！"
        log_error "  期望: $EXPECTED_FINGERPRINT"
        log_error "  实际: ${got:-<none>}"
        return 1
    fi
    log_info "GPG 密钥指纹已校验: $EXPECTED_FINGERPRINT"
    return 0
}

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "此脚本需要 root 权限运行"
        echo "请使用: sudo bash $0"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    log_step "检测操作系统..."

    if [ ! -f /etc/os-release ]; then
        log_error "无法检测操作系统版本"
        exit 1
    fi

    . /etc/os-release

    case "$ID" in
        ubuntu)
            OS="ubuntu"
            CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
            VERSION_ID_SHORT="${VERSION_ID}"

            # 验证支持的版本
            case "$VERSION_ID" in
                20.04|22.04|24.04)
                    ;;
                *)
                    log_warn "Ubuntu $VERSION_ID 未经测试，可能存在问题"
                    ;;
            esac
            ;;
        debian)
            OS="debian"
            CODENAME="$VERSION_CODENAME"
            VERSION_ID_SHORT="$VERSION_ID"

            # 验证支持的版本
            case "$VERSION_ID" in
                11|12)
                    ;;
                *)
                    log_warn "Debian $VERSION_ID 未经测试，可能存在问题"
                    ;;
            esac
            ;;
        linuxmint)
            # Linux Mint 基于 Ubuntu
            OS="ubuntu"
            case "$VERSION_ID" in
                21*) CODENAME="jammy" ;;
                22*) CODENAME="noble" ;;
                *)   CODENAME="jammy" ;;
            esac
            VERSION_ID_SHORT="$VERSION_ID"
            log_info "检测到 Linux Mint $VERSION_ID，使用 Ubuntu $CODENAME 源"
            ;;
        pop)
            # Pop!_OS 基于 Ubuntu
            OS="ubuntu"
            case "$VERSION_ID" in
                22.04) CODENAME="jammy" ;;
                24.04) CODENAME="noble" ;;
                *)     CODENAME="jammy" ;;
            esac
            VERSION_ID_SHORT="$VERSION_ID"
            log_info "检测到 Pop!_OS $VERSION_ID，使用 Ubuntu $CODENAME 源"
            ;;
        *)
            log_error "不支持的操作系统: $ID"
            echo "支持的系统: Ubuntu 20.04/22.04/24.04, Debian 11/12"
            exit 1
            ;;
    esac

    log_info "检测到: $OS $VERSION_ID_SHORT ($CODENAME)"
}

# 检查必要工具
check_dependencies() {
    log_step "检查必要工具..."

    local missing=()

    for cmd in curl gpg apt-get; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "缺少必要工具: ${missing[*]}"
        log_info "请先安装: apt-get install -y ${missing[*]}"
        exit 1
    fi
}

# 添加 GPG 密钥
add_gpg_key() {
    log_step "添加 GPG 密钥..."

    # 创建 keyrings 目录
    mkdir -p /usr/share/keyrings

    # 尝试从多个镜像下载
    local success=false
    local tmpkey
    tmpkey=$(mktemp /tmp/opentenbase-gpg-key-XXXXXX.asc)
    for url in "$GPG_KEY_URL" "https://muzimu217.github.io/OpenTenBase-deb/apt/gpg-key.asc"; do
        if curl -sL --connect-timeout 10 --max-time 30 "$url" -o "$tmpkey" 2>/dev/null && \
           [ -s "$tmpkey" ] && head -1 "$tmpkey" | grep -q "BEGIN PGP"; then
            # Pin the key: reject anything that does not match the expected
            # fingerprint before trusting it as an APT signing key.
            if ! verify_key_fingerprint "$tmpkey"; then
                rm -f "$tmpkey"
                continue
            fi
            if gpg --batch --dearmor -o "$KEYRING_PATH" < "$tmpkey" 2>/dev/null; then
                chmod 644 "$KEYRING_PATH"
                log_info "GPG 密钥已添加到: $KEYRING_PATH"
                success=true
                rm -f "$tmpkey"
                break
            fi
        fi
        rm -f "$tmpkey"
    done

    if [ "$success" != "true" ]; then
        log_error "GPG 密钥下载失败"
        echo "请检查网络连接"
        exit 1
    fi
}

# 配置 APT 源
configure_repo() {
    log_step "配置 APT 源..."

    # 备份现有配置
    if [ -f "$SOURCES_LIST" ]; then
        cp "$SOURCES_LIST" "${SOURCES_LIST}.bak"
        log_info "已备份现有配置到: ${SOURCES_LIST}.bak"
    fi

    # 写入新的源配置
    cat > "$SOURCES_LIST" << EOF
# OpenTenBase APT Repository
# Generated by setup-apt.sh on $(date -u '+%Y-%m-%d %H:%M:%S UTC')
deb [signed-by=$KEYRING_PATH] ${APT_REPO_URL} $CODENAME main
EOF

    chmod 644 "$SOURCES_LIST"
    log_info "APT 源已配置到: $SOURCES_LIST"
}

# 更新软件包列表
update_package_list() {
    log_step "更新软件包列表..."

    if apt-get update -qq 2>/dev/null; then
        log_info "软件包列表已更新"
    else
        log_warn "软件包列表更新失败，可能需要手动运行: apt-get update"
    fi
}

# 显示安装说明
show_install_info() {
    echo ""
    echo "========================================"
    echo -e "${GREEN}  OpenTenBase APT 仓库配置完成！${NC}"
    echo "========================================"
    echo ""
    echo "现在可以使用以下命令安装 OpenTenBase:"
    echo ""
    echo "  # 安装完整包（推荐）"
    echo "  sudo apt install opentenbase"
    echo ""
    echo "  # 或单独安装组件"
    echo "  sudo apt install opentenbase-server"
    echo "  sudo apt install opentenbase-client"
    echo "  sudo apt install opentenbase-contrib"
    echo ""
    echo "  # 查看可用版本"
    echo "  apt-cache search opentenbase"
    echo ""
    echo "  # 安装后快速开始"
    echo "  opentenbase-ctl init    # 初始化集群"
    echo "  opentenbase-ctl start   # 启动所有节点"
    echo "  opentenbase-ctl status  # 检查状态"
    echo ""
    echo "========================================"
}

# 主函数
main() {
    echo "========================================"
    echo "  OpenTenBase APT 仓库安装脚本"
    echo "========================================"
    echo ""

    check_root
    detect_os
    check_dependencies
    add_gpg_key
    configure_repo
    update_package_list
    show_install_info
}

# 执行主函数
main "$@"
