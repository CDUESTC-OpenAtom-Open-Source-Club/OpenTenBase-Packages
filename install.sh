#!/bin/bash
# OpenTenBase v5.0 installer — supports Ubuntu 20.04, 22.04, 24.04
# OpenTenBase v5.0 安装程序 — 支持 Ubuntu 20.04, 22.04, 24.04
# Usage: bash install.sh [directory]
#   directory: path to .deb files (default: download from GitHub)

set -e

REPO="muzimu217/opentenbase-deb"
TAG="v5.0-multi8"

echo "OpenTenBase v5.0 Installer"
echo "========================="
echo ""

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (sudo bash install.sh)" >&2
    echo "错误：必须以 root 权限运行 (sudo bash install.sh)" >&2
    exit 1
fi

# Detect Ubuntu version
if [ ! -f /etc/os-release ]; then
    echo "ERROR: cannot detect OS version (/etc/os-release not found)" >&2
    echo "错误：无法检测操作系统版本 (/etc/os-release 未找到)" >&2
    exit 1
fi

. /etc/os-release
CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

case "$CODENAME" in
    noble)  SUFFIX=".noble" ;;      # 24.04: opentenbase_5.0-1ubuntu1.noble_amd64.deb
    jammy)  SUFFIX=".jammy" ;;      # 22.04: opentenbase_5.0-1ubuntu1.jammy_amd64.deb
    focal)  SUFFIX=".focal" ;;      # 20.04: opentenbase_5.0-1ubuntu1.focal_amd64.deb
    *)
        echo "ERROR: unsupported Ubuntu version: $CODENAME" >&2
        echo "错误：不支持的 Ubuntu 版本: $CODENAME" >&2
        echo "Supported / 支持: focal (20.04), jammy (22.04), noble (24.04)" >&2
        exit 1
        ;;
esac

echo "Detected / 检测到: Ubuntu $VERSION_ID ($CODENAME)"

DIR="${1:-.}"
VER="5.0-1ubuntu1${SUFFIX}"

DEBS=(
    "opentenbase_${VER}_all.deb"
    "opentenbase-server_${VER}_amd64.deb"
    "opentenbase-client_${VER}_amd64.deb"
    "opentenbase-contrib_${VER}_amd64.deb"
)

# Check if .deb files exist, if not download from GitHub
cd "$DIR"
if [ ! -f "${DEBS[0]}" ]; then
    echo ">> Downloading packages from GitHub..."
    echo ">> 正在从 GitHub 下载软件包..."
    for deb in "${DEBS[@]}"; do
        echo "  $deb"
        curl -sLO "https://github.com/${REPO}/releases/download/${TAG}/${deb}"
    done
    echo ""
fi

# Verify files exist
missing=0
for deb in "${DEBS[@]}"; do
    if [ ! -f "$deb" ]; then
        echo "ERROR: $deb not found" >&2
        echo "错误：$deb 未找到" >&2
        missing=1
    fi
done
[ $missing -eq 1 ] && exit 1

# Install with automatic dependency resolution
echo ">> Installing packages and dependencies..."
echo ">> 正在安装软件包和依赖..."
apt-get update -qq 2>/dev/null || true
apt-get install -y -qq ./*.deb

echo ""
echo ">> Installation complete!"
echo ">> 安装完成！"
echo ""
echo "Quick start / 快速开始:"
echo "  opentenbase-ctl init    # Initialize cluster / 初始化集群"
echo "  opentenbase-ctl start   # Start all nodes / 启动所有节点"
echo "  opentenbase-ctl status  # Check status / 检查状态"
echo ""
echo "Connect / 连接:"
echo "  opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres"
