#!/bin/bash
# OpenTenBase APT 仓库搭建脚本
# 用法: ./setup-apt-repo.sh [选项]

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

# 显示帮助
show_help() {
    echo "OpenTenBase APT 仓库搭建脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -d, --dir DIR          指定仓库目录 (默认: ./repo)"
    echo "  -g, --gpg-key KEY      指定 GPG 密钥 ID"
    echo "  -n, --name NAME        指定仓库名称 (默认: opentenbase)"
    echo "  -u, --url URL          指定仓库 URL"
    echo "  -p, --packages DIR     指定软件包目录"
    echo "  -h, --help             显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -d /var/www/repo -g ABCD1234"
    echo "  $0 --url https://opentenbase.org/repo/apt"
}

# 检查依赖
check_dependencies() {
    log_step "检查依赖..."
    
    local deps=("reprepro" "gpg" "dpkg-scanpackages")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "缺少依赖: ${missing[*]}"
        echo ""
        echo "请安装缺少的依赖:"
        echo "  sudo apt-get install -y reprepro gnupg dpkg-dev"
        return 1
    fi
    
    log_info "依赖检查通过"
}

# 创建仓库目录结构
create_repo_structure() {
    local repo_dir=$1
    local repo_name=$2
    
    log_step "创建仓库目录结构..."
    
    mkdir -p "$repo_dir/conf"
    mkdir -p "$repo_dir/db"
    mkdir -p "$repo_dir/dists"
    mkdir -p "$repo_dir/pool/main"
    
    log_info "目录结构已创建: $repo_dir"
}

# 创建仓库配置文件
create_repo_config() {
    local repo_dir=$1
    local repo_name=$2
    local gpg_key=$3
    
    log_step "创建仓库配置文件..."
    
    cat > "$repo_dir/conf/distributions" << EOF
Origin: OpenTenBase
Label: OpenTenBase
Codename: focal
Architectures: amd64
Components: main
Description: OpenTenBase v5.0 packages for Ubuntu 20.04 (Focal)
SignWith: $gpg_key

Origin: OpenTenBase
Label: OpenTenBase
Codename: jammy
Architectures: amd64
Components: main
Description: OpenTenBase v5.0 packages for Ubuntu 22.04 (Jammy)
SignWith: $gpg_key

Origin: OpenTenBase
Label: OpenTenBase
Codename: noble
Architectures: amd64
Components: main
Description: OpenTenBase v5.0 packages for Ubuntu 24.04 (Noble)
SignWith: $gpg_key

Origin: OpenTenBase
Label: OpenTenBase
Codename: bullseye
Architectures: amd64
Components: main
Description: OpenTenBase v5.0 packages for Debian 11 (Bullseye)
SignWith: $gpg_key

Origin: OpenTenBase
Label: OpenTenBase
Codename: bookworm
Architectures: amd64
Components: main
Description: OpenTenBase v5.0 packages for Debian 12 (Bookworm)
SignWith: $gpg_key
EOF
    
    log_info "配置文件已创建: $repo_dir/conf/distributions"
}

# 添加软件包到仓库
add_packages() {
    local repo_dir=$1
    local packages_dir=$2
    
    log_step "添加软件包到仓库..."
    
    if [ ! -d "$packages_dir" ]; then
        log_error "软件包目录不存在: $packages_dir"
        return 1
    fi
    
    local count=0
    for deb in "$packages_dir"/*.deb; do
        if [ -f "$deb" ]; then
            log_info "添加: $(basename $deb)"
            reprepro -b "$repo_dir" includedeb focal "$deb" 2>/dev/null || \
            reprepro -b "$repo_dir" includedeb jammy "$deb" 2>/dev/null || \
            reprepro -b "$repo_dir" includedeb noble "$deb" 2>/dev/null || \
            reprepro -b "$repo_dir" includedeb bullseye "$deb" 2>/dev/null || \
            reprepro -b "$repo_dir" includedeb bookworm "$deb" 2>/dev/null || \
            log_warn "无法添加: $(basename $deb)"
            ((count++))
        fi
    done
    
    log_info "已添加 $count 个软件包"
}

# 生成仓库索引
generate_index() {
    local repo_dir=$1
    
    log_step "生成仓库索引..."
    
    cd "$repo_dir"
    reprepro -b . export
    
    log_info "仓库索引已生成"
}

# 创建安装脚本模板
create_install_script() {
    local repo_dir=$1
    local repo_url=$2
    
    log_step "创建安装脚本模板..."
    
    cat > "$repo_dir/setup.sh" << 'EOF'
#!/bin/bash
# OpenTenBase 一键安装脚本
# Usage: curl -sSL https://opentenbase.org/repo/setup.sh | sudo bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "必须以 root 权限运行此脚本"
        exit 1
    fi
}

# 检测系统版本
detect_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "无法检测操作系统版本"
        exit 1
    fi

    . /etc/os-release
    
    case "$ID" in
        ubuntu)
            OS="ubuntu"
            CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
            ;;
        debian)
            OS="debian"
            CODENAME="$VERSION_CODENAME"
            ;;
        *)
            log_error "不支持的操作系统: $ID"
            exit 1
            ;;
    esac

    log_info "检测到: $OS $VERSION_ID ($CODENAME)"
}

# 添加 GPG 密钥
add_gpg_key() {
    log_info "添加 GPG 密钥..."
    
    curl -fsSL https://opentenbase.org/repo/gpg-key.asc | \
        gpg --dearmor -o /usr/share/keyrings/opentenbase-archive-keyring.gpg
    
    chmod 644 /usr/share/keyrings/opentenbase-archive-keyring.gpg
}

# 配置仓库源
configure_repo() {
    log_info "配置仓库源..."
    
    echo "deb [signed-by=/usr/share/keyrings/opentenbase-archive-keyring.gpg] \
        https://opentenbase.org/repo/apt $CODENAME main" \
        > /etc/apt/sources.list.d/opentenbase.list
    
    chmod 644 /etc/apt/sources.list.d/opentenbase.list
}

# 安装 OpenTenBase
install_opentenbase() {
    log_info "更新软件包列表..."
    apt-get update -qq
    
    log_info "安装 OpenTenBase..."
    apt-get install -y opentenbase
    
    log_info "安装完成！"
    echo ""
    echo "快速开始:"
    echo "  opentenbase-ctl init    # 初始化集群"
    echo "  opentenbase-ctl start   # 启动所有节点"
    echo "  opentenbase-ctl status  # 检查状态"
    echo ""
    echo "连接数据库:"
    echo "  opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres"
}

# 主函数
main() {
    echo "========================================"
    echo "  OpenTenBase 一键安装脚本"
    echo "========================================"
    echo ""
    
    check_root
    detect_os
    add_gpg_key
    configure_repo
    install_opentenbase
}

# 执行主函数
main "$@"
EOF
    
    chmod +x "$repo_dir/setup.sh"
    log_info "安装脚本已创建: $repo_dir/setup.sh"
}

# 创建 README 文件
create_readme() {
    local repo_dir=$1
    
    log_step "创建 README 文件..."
    
    cat > "$repo_dir/README.md" << 'EOF'
# OpenTenBase APT 仓库

## 安装方法

### 一键安装（推荐）

```bash
curl -sSL https://opentenbase.org/repo/setup.sh | sudo bash
```

### 手动安装

1. 添加 GPG 密钥：

```bash
curl -fsSL https://opentenbase.org/repo/gpg-key.asc | \
    sudo gpg --dearmor -o /usr/share/keyrings/opentenbase-archive-keyring.gpg
```

2. 添加仓库源：

```bash
echo "deb [signed-by=/usr/share/keyrings/opentenbase-archive-keyring.gpg] \
    https://opentenbase.org/repo/apt $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/opentenbase.list
```

3. 安装软件包：

```bash
sudo apt update
sudo apt install opentenbase
```

## 支持的发行版

- Ubuntu 20.04 (Focal)
- Ubuntu 22.04 (Jammy)
- Ubuntu 24.04 (Noble)
- Debian 11 (Bullseye)
- Debian 12 (Bookworm)

## 快速开始

```bash
# 初始化集群
opentenbase-ctl init

# 启动所有节点
opentenbase-ctl start

# 检查状态
opentenbase-ctl status

# 连接数据库
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres
```

## 更多信息

- [GitHub 仓库](https://github.com/muzimu217/OpenTenBase-deb)
- [文档](https://github.com/muzimu217/OpenTenBase-deb/blob/main/README.md)
EOF
    
    log_info "README 文件已创建"
}

# 主函数
main() {
    local repo_dir="./repo"
    local gpg_key=""
    local repo_name="opentenbase"
    local repo_url=""
    local packages_dir=""
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dir)
                repo_dir="$2"
                shift 2
                ;;
            -g|--gpg-key)
                gpg_key="$2"
                shift 2
                ;;
            -n|--name)
                repo_name="$2"
                shift 2
                ;;
            -u|--url)
                repo_url="$2"
                shift 2
                ;;
            -p|--packages)
                packages_dir="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo "========================================"
    log_step "OpenTenBase APT 仓库搭建"
    echo "========================================"
    echo ""
    
    # 检查依赖
    check_dependencies
    
    # 创建仓库目录结构
    create_repo_structure "$repo_dir" "$repo_name"
    
    # 创建仓库配置文件
    create_repo_config "$repo_dir" "$repo_name" "$gpg_key"
    
    # 如果指定了软件包目录，添加软件包
    if [ -n "$packages_dir" ]; then
        add_packages "$repo_dir" "$packages_dir"
    fi
    
    # 生成仓库索引
    generate_index "$repo_dir"
    
    # 创建安装脚本
    create_install_script "$repo_dir" "$repo_url"
    
    # 创建 README
    create_readme "$repo_dir"
    
    echo ""
    echo "========================================"
    log_info "APT 仓库搭建完成！"
    echo "========================================"
    echo ""
    echo "仓库目录: $repo_dir"
    echo ""
    echo "下一步:"
    echo "1. 将仓库目录上传到 Web 服务器"
    echo "2. 配置域名（可选）"
    echo "3. 测试安装脚本"
    echo ""
    echo "测试安装:"
    echo "  curl -sSL $repo_dir/setup.sh | sudo bash"
}

# 执行主函数
main "$@"
