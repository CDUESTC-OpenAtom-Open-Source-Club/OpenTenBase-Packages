#!/bin/bash
# OpenTenBase installer — supports Ubuntu 20.04/22.04/24.04, Debian 11/12
# Supports multi-version installation (side-by-side)
# Usage: bash install.sh [--version VERSION] [directory]
#   --version VERSION: OpenTenBase version to install (default: 5.0)
#   directory: path to .deb files (default: download from GitHub)

set -e

REPO="muzimu217/OpenTenBase-deb"
DEFAULT_VERSION="5.0"
DEFAULT_TAG="v5.0-multi10"

# Parse arguments
VERSION=""
DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: bash install.sh [--version VERSION] [directory]"
            echo ""
            echo "Options:"
            echo "  --version VERSION  OpenTenBase version to install (default: $DEFAULT_VERSION)"
            echo "  directory          Path to .deb files (default: download from GitHub)"
            echo ""
            echo "Examples:"
            echo "  bash install.sh                    # Install default version ($DEFAULT_VERSION)"
            echo "  bash install.sh --version 5.0      # Install v5.0 (latest)"
            echo "  bash install.sh --version 2.6.0    # Install v2.6.0"
            echo "  bash install.sh /path/to/debs      # Install from local directory"
            exit 0
            ;;
        *)
            DIR="$1"
            shift
            ;;
    esac
done

VERSION="${VERSION:-$DEFAULT_VERSION}"

# Map version to release tag
# Supported OpenTenBase versions: 5.0 (latest), 2.6.0, 2.5.0
case "$VERSION" in
    5.0)    TAG="v5.0-multi10" ;;
    2.6.0)  TAG="v2.6.0-multi1" ;;
    2.5.0)  TAG="v2.5.0-multi1" ;;
    *)      TAG="v${VERSION}-multi1" ;;
esac

echo "OpenTenBase v${VERSION} Installer"
echo "=================================="
echo ""

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (sudo bash install.sh)" >&2
    echo "错误：必须以 root 权限运行 (sudo bash install.sh)" >&2
    exit 1
fi

# Detect OS version
if [ ! -f /etc/os-release ]; then
    echo "ERROR: cannot detect OS version (/etc/os-release not found)" >&2
    echo "错误：无法检测操作系统版本 (/etc/os-release 未找到)" >&2
    exit 1
fi

. /etc/os-release
CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

# Determine package type and suffix
case "$ID" in
    ubuntu|debian)
        PKG_TYPE="deb"
        case "$CODENAME" in
            noble)    SUFFIX=".noble" ;;
            jammy)    SUFFIX=".jammy" ;;
            focal)    SUFFIX=".focal" ;;
            bookworm) SUFFIX=".bookworm" ;;
            bullseye) SUFFIX=".bullseye" ;;
            bionic)   SUFFIX=".bionic" ;;
            *)
                echo "ERROR: unsupported version: $CODENAME" >&2
                echo "错误：不支持的版本: $CODENAME" >&2
                echo "Supported / 支持: focal (20.04), jammy (22.04), noble (24.04), bullseye (11), bookworm (12)" >&2
                exit 1
                ;;
        esac
        ;;
    centos|rocky|almalinux|fedora|rhel|ol|amzn|openEuler)
        PKG_TYPE="rpm"
        SUFFIX=""
        ;;
    *)
        # Try ID_LIKE for derivative distros
        case "$ID_LIKE" in
            *debian*|*ubuntu*)
                PKG_TYPE="deb"
                SUFFIX=".$CODENAME"
                ;;
            *rhel*|*centos*|*fedora*)
                PKG_TYPE="rpm"
                SUFFIX=""
                ;;
            *)
                echo "ERROR: unsupported distribution: $ID" >&2
                exit 1
                ;;
        esac
        ;;
esac

echo "Detected / 检测到: $ID $VERSION_ID ($CODENAME) — $PKG_TYPE packages"

# Install function for DEB
install_deb() {
    local ver="${VERSION}-1ubuntu1${SUFFIX}"

    DEBS=(
        "opentenbase_${ver}_all.deb"
        "opentenbase-server_${ver}_amd64.deb"
        "opentenbase-client_${ver}_amd64.deb"
        "opentenbase-contrib_${ver}_amd64.deb"
    )

    local dir="${DIR:-.}"
    cd "$dir"

    if [ ! -f "${DEBS[0]}" ]; then
        DLDIR=$(mktemp -d)
        echo ">> Downloading packages from GitHub..."
        echo ">> 正在从 GitHub 下载软件包..."
        for deb in "${DEBS[@]}"; do
            echo "  $deb"
            curl -sL -o "${DLDIR}/${deb}" "https://github.com/${REPO}/releases/download/${TAG}/${deb}"
        done
        echo ""
        cd "$DLDIR"
    fi

    # Verify files exist
    local missing=0
    for deb in "${DEBS[@]}"; do
        if [ ! -f "$deb" ]; then
            echo "ERROR: $deb not found" >&2
            missing=1
        fi
    done
    [ $missing -eq 1 ] && exit 1

    # Install with automatic dependency resolution
    echo ">> Installing packages and dependencies..."
    echo ">> 正在安装软件包和依赖..."
    apt-get update -qq 2>/dev/null || true
    apt-get install -y -qq ./*.deb
}

# Install function for RPM
install_rpm() {
    local ver="${VERSION}.0-1"
    local arch=$(uname -m)

    RPMS=(
        "opentenbase-${ver}.${arch}.rpm"
    )

    local dir="${DIR:-.}"
    cd "$dir"

    if [ ! -f "${RPMS[0]}" ]; then
        DLDIR=$(mktemp -d)
        echo ">> Downloading packages from GitHub..."
        for rpm in "${RPMS[@]}"; do
            echo "  $rpm"
            curl -sL -o "${DLDIR}/${rpm}" "https://github.com/${REPO}/releases/download/${TAG}/${rpm}"
        done
        cd "$DLDIR"
    fi

    echo ">> Installing packages..."
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y ./*.rpm
    elif command -v yum >/dev/null 2>&1; then
        yum install -y ./*.rpm
    else
        rpm -ivh ./*.rpm
    fi
}

# Run installation
case "$PKG_TYPE" in
    deb) install_deb ;;
    rpm) install_rpm ;;
esac

echo ""
echo ">> Installation complete! (v${VERSION})"
echo ">> 安装完成！(v${VERSION})"
echo ""
echo "Version management / 版本管理:"
echo "  opentenbase-switch-version          # List installed versions / 列出已安装版本"
echo "  opentenbase-switch-version ${VERSION}       # Switch to v${VERSION} / 切换到 v${VERSION}"
echo ""
echo "Quick start / 快速开始:"
echo "  opentenbase-ctl init    # Initialize cluster / 初始化集群"
echo "  opentenbase-ctl start   # Start all nodes / 启动所有节点"
echo "  opentenbase-ctl status  # Check status / 检查状态"
echo ""
echo "Connect / 连接:"
echo "  opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres"
