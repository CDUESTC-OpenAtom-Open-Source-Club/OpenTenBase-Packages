#!/bin/bash
# =============================================================================
# OpenTenBase 源码编译脚本
# =============================================================================
# 用法:
#   curl -sSL <url>/build-from-source.sh | sudo bash
#   sudo bash build-from-source.sh [--version VERSION]
#
# 用于开发者二次开发和贡献代码
# =============================================================================

set -euo pipefail

VERSION="${1:-5.0}"
INSTALL_PREFIX="/usr/local/opentenbase-${VERSION}"
BUILD_DIR="/tmp/opentenbase-build"

echo "========================================"
echo "  OpenTenBase 源码编译脚本"
echo "========================================"
echo ""
echo "版本: ${VERSION}"
echo "安装路径: ${INSTALL_PREFIX}"
echo ""

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo "错误: 请使用 root 用户运行: sudo bash $0"
    exit 1
fi

# 安装编译依赖
echo "[1/6] 安装编译依赖..."
if command -v apt-get &>/dev/null; then
    apt-get update
    apt-get install -y \
        build-essential \
        cmake \
        git \
        libreadline-dev \
        zlib1g-dev \
        libssl-dev \
        libxml2-dev \
        libxslt1-dev \
        libuuid-dev \
        flex \
        bison \
        pkg-config
elif command -v dnf &>/dev/null; then
    dnf install -y \
        gcc \
        gcc-c++ \
        make \
        cmake \
        git \
        readline-devel \
        zlib-devel \
        openssl-devel \
        libxml2-devel \
        libxslt-devel \
        libuuid-devel \
        flex \
        bison \
        pkgconfig
elif command -v yum &>/dev/null; then
    yum install -y \
        gcc \
        gcc-c++ \
        make \
        cmake \
        git \
        readline-devel \
        zlib-devel \
        openssl-devel \
        libxml2-devel \
        libxslt-devel \
        libuuid-devel \
        flex \
        bison \
        pkgconfig
else
    echo "错误: 不支持的操作系统"
    exit 1
fi

echo "[✓] 编译依赖安装完成"

# 克隆源码
echo "[2/6] 克隆 OpenTenBase 源码..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

git clone https://github.com/OpenTenBase/OpenTenBase.git .
echo "[✓] 源码克隆完成"

# 检出指定版本
echo "[3/6] 检出版本 ${VERSION}..."
case "${VERSION}" in
    5.0)
        # 5.0 是最新版本，无需检出
        ;;
    2.6.0)
        git checkout V2.6.0 || git checkout v2.6.0 || true
        ;;
    2.5.0)
        git checkout V2.5.0 || git checkout v2.5.0 || true
        ;;
    *)
        echo "警告: 未知版本 ${VERSION}，使用默认分支"
        ;;
esac
echo "[✓] 版本检出完成"

# 配置编译选项
echo "[4/6] 配置编译选项..."
mkdir -p build
cd build

cmake .. \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_DEBUG=OFF \
    -DWITH_SSL=ON \
    -DWITH_ZLIB=ON \
    -DWITH_READLINE=ON

echo "[✓] 编译配置完成"

# 编译
echo "[5/6] 编译 OpenTenBase..."
make -j$(nproc)
echo "[✓] 编译完成"

# 安装
echo "[6/6] 安装到 ${INSTALL_PREFIX}..."
make install
echo "[✓] 安装完成"

# 创建符号链接
ln -sf "${INSTALL_PREFIX}" /usr/local/opentenbase
echo "[✓] 符号链接已创建"

# 添加到 PATH
if ! grep -q "opentenbase" /etc/profile.d/opentenbase.sh 2>/dev/null; then
    cat > /etc/profile.d/opentenbase.sh << 'EOF'
export PATH=/usr/local/opentenbase/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/opentenbase/lib:$LD_LIBRARY_PATH
EOF
    echo "[✓] PATH 已配置"
fi

# 清理
cd /
rm -rf "${BUILD_DIR}"

echo ""
echo "========================================"
echo "  ✅ OpenTenBase 编译安装完成"
echo "========================================"
echo ""
echo "安装路径: ${INSTALL_PREFIX}"
echo ""
echo "下一步:"
echo "  source /etc/profile.d/opentenbase.sh"
echo "  opentenbase_ctl --help  # 查看帮助"
echo "  或使用一键部署脚本: opentenbase.sh install"
echo ""
echo "开发建议:"
echo "  - 源码位置: https://github.com/OpenTenBase/OpenTenBase"
echo "  - 贡献代码: fork → branch → PR"
echo "  - 文档: https://github.com/OpenTenBase/OpenTenBase/wiki"
echo ""