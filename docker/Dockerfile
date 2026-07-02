# OpenTenBase Docker Image
# 直接从 RPM 包安装

FROM rockylinux:9

# 安装构建依赖 + 运行依赖
RUN yum install -y \
    gcc \
    make \
    cmake \
    openssl-devel \
    gnupg2 \
    libatomic \
    libpq \
    && yum clean all

# 编译安装 libssh2 (Rocky 9 不提供 libssh2，只有新版 libssh)
# OpenTenBase 运行时依赖 libssh2.so.1
RUN cd /tmp && \
    curl -fsSL https://github.com/libssh2/libssh2/releases/download/libssh2-1.11.1/libssh2-1.11.1.tar.gz -o libssh2.tar.gz && \
    tar xzf libssh2.tar.gz && \
    cd libssh2-1.11.1 && \
    cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_SHARED_LIBS=ON && \
    cmake --build build -j$(nproc) && \
    cmake --install build && \
    ldconfig && \
    cd /tmp && rm -rf libssh2-*

# 配置 OpenTenBase 仓库
RUN curl -fsSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh | bash

# 安装 OpenTenBase
RUN yum install -y opentenbase-5.0

# 创建数据目录
RUN mkdir -p /data/gtm /data/coord /data/dn1 && \
    chmod 755 /data

# 设置环境变量
ENV PATH="/usr/lib/opentenbase/5.0/bin:$PATH"
ENV LD_LIBRARY_PATH="/usr/lib/opentenbase/5.0/lib:$LD_LIBRARY_PATH"

# 默认用户
USER root

WORKDIR /data

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pg_isready -h localhost -p 5432 || exit 1