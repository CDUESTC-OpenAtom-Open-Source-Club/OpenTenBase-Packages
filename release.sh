#!/bin/bash
# OpenTenBase 版本发布脚本
# Usage: ./release.sh [version]
# Example: ./release.sh v5.0-multi9

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
    echo "OpenTenBase 版本发布脚本"
    echo ""
    echo "用法: $0 [选项] <version>"
    echo ""
    echo "选项:"
    echo "  -d, --dry-run          模拟运行，不实际执行"
    echo "  -f, --force            强制执行，跳过确认"
    echo "  -m, --message MESSAGE  指定发布说明"
    echo "  -h, --help             显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 v5.0-multi9"
    echo "  $0 -m 'Bug fixes and improvements' v5.0-multi9"
    echo "  $0 --dry-run v5.0-multi9"
}

# 验证版本格式
validate_version() {
    local version=$1
    
    if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+-[a-zA-Z0-9]+$ ]]; then
        log_error "版本格式不正确: $version"
        echo "正确的格式: v5.0-multi9, v5.0-1ubuntu1, etc."
        return 1
    fi
}

# 检查 Git 状态
check_git_status() {
    log_step "检查 Git 状态..."
    
    # 检查是否在 Git 仓库中
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "当前目录不是 Git 仓库"
        return 1
    fi
    
    # 检查是否有未提交的更改
    if [ -n "$(git status --porcelain)" ]; then
        log_warn "有未提交的更改:"
        git status --short
        echo ""
        read -p "是否继续？(y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "已取消"
            return 1
        fi
    fi
    
    # 检查是否在 main 分支
    local current_branch=$(git branch --show-current)
    if [ "$current_branch" != "main" ]; then
        log_warn "当前不在 main 分支 (当前: $current_branch)"
        read -p "是否继续？(y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "已取消"
            return 1
        fi
    fi
}

# 创建发布说明
create_release_notes() {
    local version=$1
    local message=$2
    
    log_step "创建发布说明..."
    
    # 获取上一个版本
    local prev_version=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    
    if [ -n "$prev_version" ]; then
        echo "## Changes since $prev_version"
        echo ""
        git log "$prev_version..HEAD" --pretty=format:"- %s (%h)" --no-merges
        echo ""
    fi
    
    if [ -n "$message" ]; then
        echo "## Release Notes"
        echo ""
        echo "$message"
        echo ""
    fi
    
    echo "## Installation"
    echo ""
    echo "### One-click Install (Recommended)"
    echo ""
    echo '```bash'
    echo "curl -sLO https://github.com/muzimu217/opentenbase-deb/releases/download/$version/install.sh"
    echo "sudo bash install.sh"
    echo '```'
    echo ""
    echo "### Supported Distributions"
    echo ""
    echo "- Ubuntu 20.04 (Focal)"
    echo "- Ubuntu 22.04 (Jammy)"
    echo "- Ubuntu 24.04 (Noble)"
    echo "- Debian 11 (Bullseye)"
    echo "- Debian 12 (Bookworm)"
    echo ""
    echo "### Documentation"
    echo ""
    echo "- [English Documentation](README.md)"
    echo "- [中文文档](README_zh.md)"
    echo "- [Roadmap](ROADMAP.md)"
    echo "- [Contributing Guide](CONTRIBUTING.md)"
}

# 创建 Git 标签
create_tag() {
    local version=$1
    local release_notes=$2
    local dry_run=$3
    
    log_step "创建 Git 标签: $version"
    
    if [ "$dry_run" = true ]; then
        log_info "[DRY RUN] 将创建标签: $version"
        return 0
    fi
    
    # 创建带注释的标签
    git tag -a "$version" -m "$release_notes"
    
    log_info "标签已创建: $version"
}

# 推送标签
push_tag() {
    local version=$1
    local dry_run=$2
    
    log_step "推送标签到远程仓库..."
    
    if [ "$dry_run" = true ]; then
        log_info "[DRY RUN] 将推送标签: $version"
        return 0
    fi
    
    git push origin "$version"
    
    log_info "标签已推送: $version"
}

# 更新 install.sh 中的 TAG
update_install_script() {
    local version=$1
    local dry_run=$2
    
    log_step "更新 install.sh 中的 TAG..."
    
    if [ "$dry_run" = true ]; then
        log_info "[DRY RUN] 将更新 install.sh: TAG=$version"
        return 0
    fi
    
    # 更新 TAG
    sed -i '' "s/TAG=\".*\"/TAG=\"$version\"/" install.sh
    
    # 提交更改
    git add install.sh
    git commit -m "chore: update install.sh TAG to $version"
    
    log_info "install.sh 已更新"
}

# 主函数
main() {
    local version=""
    local message=""
    local dry_run=false
    local force=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -m|--message)
                message="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
            *)
                if [ -z "$version" ]; then
                    version="$1"
                else
                    log_error "多余的参数: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # 检查版本参数
    if [ -z "$version" ]; then
        log_error "请指定版本号"
        show_help
        exit 1
    fi
    
    # 验证版本格式
    validate_version "$version"
    
    # 检查 Git 状态
    check_git_status
    
    # 创建发布说明
    local release_notes=$(create_release_notes "$version" "$message")
    
    # 显示发布信息
    echo ""
    echo "========================================"
    log_step "发布信息"
    echo "========================================"
    echo "版本: $version"
    echo ""
    echo "发布说明:"
    echo "$release_notes"
    echo "========================================"
    echo ""
    
    # 确认发布
    if [ "$force" != true ]; then
        read -p "确认发布？(y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "已取消发布"
            exit 0
        fi
    fi
    
    # 更新 install.sh
    update_install_script "$version" "$dry_run"
    
    # 创建标签
    create_tag "$version" "$release_notes" "$dry_run"
    
    # 推送标签
    push_tag "$version" "$dry_run"
    
    echo ""
    echo "========================================"
    log_info "发布完成！"
    echo "========================================"
    echo ""
    echo "下一步:"
    echo "1. 等待 CI 构建完成"
    echo "2. 检查 GitHub Releases 页面"
    echo "3. 测试安装脚本"
    echo ""
    echo "CI 构建状态:"
    echo "https://github.com/muzimu217/opentenbase-deb/actions"
}

# 执行主函数
main "$@"
