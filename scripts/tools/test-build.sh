#!/bin/bash
# OpenTenBase 本地构建测试脚本
# Usage: ./test-build.sh [distro] [version]
# Example: ./test-build.sh ubuntu 20.04

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
    echo "OpenTenBase 本地构建测试脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -d, --distro DISTRO    指定发行版 (ubuntu/debian)"
    echo "  -v, --version VERSION  指定版本 (20.04/22.04/24.04/11/12)"
    echo "  -a, --all              测试所有支持的发行版"
    echo "  -c, --clean            清理构建产物"
    echo "  -h, --help             显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 -d ubuntu -v 20.04"
    echo "  $0 -d debian -v 12"
    echo "  $0 --all"
}

# 支持的发行版本
SUPPORTED_DISTROS=(
    "ubuntu:20.04:focal"
    "ubuntu:22.04:jammy"
    "ubuntu:24.04:noble"
    "debian:11:bullseye"
    "debian:12:bookworm"
)

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker 服务未启动，请启动 Docker"
        exit 1
    fi
}

# 检查源码目录
check_source() {
    if [ ! -d "source" ]; then
        log_step "克隆 OpenTenBase 源码..."
        git clone --depth=1 https://github.com/OpenTenBase/OpenTenBase.git source
    fi
}

# 构建单个发行版
build_distro() {
    local distro=$1
    local version=$2
    local codename=$3
    local dockerfile="docker-${distro}-${version}.Dockerfile"
    
    log_step "构建 ${distro} ${version} (${codename})..."
    
    # 检查 Dockerfile 是否存在
    if [ ! -f "$dockerfile" ]; then
        log_error "Dockerfile 不存在: $dockerfile"
        return 1
    fi
    
    # 创建输出目录
    mkdir -p "output/${codename}"
    
    # 构建 Docker 镜像
    log_info "构建 Docker 镜像..."
    docker build \
        -f "$dockerfile" \
        -t "opentenbase-builder:${distro}-${version}" \
        .
    
    # 运行构建
    log_info "运行构建..."
    docker run \
        --rm \
        -v "$(pwd)/source:/source" \
        -v "$(pwd)/output/${codename}:/output" \
        "opentenbase-builder:${distro}-${version}"
    
    # 验证构建结果
    log_info "验证构建结果..."
    local deb_count=$(ls -1 "output/${codename}"/*.deb 2>/dev/null | wc -l)
    
    if [ "$deb_count" -gt 0 ]; then
        log_info "✓ ${distro} ${version} 构建成功，生成 ${deb_count} 个 .deb 包"
        ls -lh "output/${codename}"/*.deb
    else
        log_error "✗ ${distro} ${version} 构建失败，未生成 .deb 包"
        return 1
    fi
}

# 测试所有发行版
test_all() {
    local success_count=0
    local fail_count=0
    
    for distro_info in "${SUPPORTED_DISTROS[@]}"; do
        IFS=':' read -r distro version codename <<< "$distro_info"
        
        echo ""
        echo "========================================"
        log_step "测试 ${distro} ${version} (${codename})"
        echo "========================================"
        
        if build_distro "$distro" "$version" "$codename"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    echo ""
    echo "========================================"
    log_info "测试完成！"
    echo "========================================"
    log_info "成功: ${success_count}"
    log_info "失败: ${fail_count}"
    
    if [ "$fail_count" -gt 0 ]; then
        return 1
    fi
}

# 清理构建产物
clean_build() {
    log_step "清理构建产物..."
    
    # 删除输出目录
    rm -rf output/
    
    # 删除 Docker 镜像
    for distro_info in "${SUPPORTED_DISTROS[@]}"; do
        IFS=':' read -r distro version codename <<< "$distro_info"
        docker rmi "opentenbase-builder:${distro}-${version}" 2>/dev/null || true
    done
    
    log_info "清理完成"
}

# 主函数
main() {
    local distro=""
    local version=""
    local test_all=false
    local clean=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--distro)
                distro="$2"
                shift 2
                ;;
            -v|--version)
                version="$2"
                shift 2
                ;;
            -a|--all)
                test_all=true
                shift
                ;;
            -c|--clean)
                clean=true
                shift
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
    
    # 检查 Docker
    check_docker
    
    # 清理模式
    if [ "$clean" = true ]; then
        clean_build
        exit 0
    fi
    
    # 测试所有发行版
    if [ "$test_all" = true ]; then
        check_source
        test_all
        exit $?
    fi
    
    # 测试单个发行版
    if [ -n "$distro" ] && [ -n "$version" ]; then
        # 查找对应的 codename
        local codename=""
        for distro_info in "${SUPPORTED_DISTROS[@]}"; do
            IFS=':' read -r d v c <<< "$distro_info"
            if [ "$d" = "$distro" ] && [ "$v" = "$version" ]; then
                codename="$c"
                break
            fi
        done
        
        if [ -z "$codename" ]; then
            log_error "不支持的发行版: ${distro} ${version}"
            echo "支持的发行版:"
            for distro_info in "${SUPPORTED_DISTROS[@]}"; do
                IFS=':' read -r d v c <<< "$distro_info"
                echo "  - ${d} ${v} (${c})"
            done
            exit 1
        fi
        
        check_source
        build_distro "$distro" "$version" "$codename"
        exit $?
    fi
    
    # 如果没有参数，显示帮助
    show_help
}

# 执行主函数
main "$@"
