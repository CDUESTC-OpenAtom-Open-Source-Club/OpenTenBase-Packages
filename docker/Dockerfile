# OpenTenBase Docker Image
# 直接从 RPM 包安装

FROM rockylinux:9

# 复制 libssh2 源码（Rocky 9 不提供 libssh2，需要自行编译）
COPY libssh2-1.11.1.tar.gz /tmp/libssh2.tar.gz

# 安装构建依赖 + 运行依赖 + RPM 构建工具
RUN yum install -y \
    gcc \
    make \
    cmake \
    openssl-devel \
    gnupg2 \
    libatomic \
    libpq \
    rpm-build \
    && yum clean all

# 编译安装 libssh2 (Rocky 9 不提供 libssh2，只有新版 libssh)
# OpenTenBase 运行时依赖 libssh2.so.1
RUN cd /tmp && \
    tar xzf libssh2.tar.gz && \
    cd libssh2-1.11.1 && \
    cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_SHARED_LIBS=ON && \
    cmake --build build -j$(nproc) && \
    cmake --install build && \
    ldconfig && \
    cd /tmp && rm -rf libssh2-* libssh2.tar.gz

# 创建 libssh2 虚拟 RPM 包 (让 RPM 包管理器"看到"libssh2.so.1)
# 实际库文件由上面的源码编译提供
RUN mkdir -p /tmp/libssh2-dummy/SPECS && \
    echo 'Name:           libssh2-dummy' > /tmp/libssh2-dummy/SPECS/libssh2-dummy.spec && \
    echo 'Version:        1.11.1' >> /tmp/libssh2-dummy/SPECS/libssh2-dummy.spec && \
    echo 'Release:        1' >> /tmp/libssh2-dummy/SPECS/libssh2-dummy.spec && \
    echo 'Summary:        Dummy package providing libssh2.so.1 (built from source)' >> /tmp/libssh2-dummy/SPECS/libssh2-dummy.spec && \
    echo 'License:        BSD' >> /tmp/libssh2-dummy/SPECS/libssh2-dummy.spec && \
    echo 'Provides:       libssh2.so.1()(64bit)' >> /tmp/libssh2-dummy/SPECS/libssh2-dummy.spec && \
    echo 'Provides:       libssh2 = %{version}' >> /tmp/libssh2-dummy/SPECS/libssh2-dummy.spec && \
    echo '%description' >> /tmp/libssh2-dummy/SPECS/libssh2-dummy.spec && \
    echo 'Dummy RPM package that provides libssh2.so.1 capability.' >> /tmp/libssh2-dummy/SPECS/libssh2-dummy.spec && \
    echo 'The actual library is built from source and installed outside RPM.' >> /tmp/libssh2-dummy/SPECS/libssh2-dummy.spec && \
    echo '%files' >> /tmp/libssh2-dummy/SPECS/libssh2-dummy.spec && \
    rpmbuild --define '_rpmdir /tmp/libssh2-dummy/RPMS' \
             --define '_builddir /tmp/libssh2-dummy/BUILD' \
             --define '_sourcedir /tmp/libssh2-dummy/SOURCES' \
             --define '_specdir /tmp/libssh2-dummy/SPECS' \
             --define '_srcrpmdir /tmp/libssh2-dummy/SRPMS' \
             -bb /tmp/libssh2-dummy/SPECS/libssh2-dummy.spec && \
    yum install -y /tmp/libssh2-dummy/RPMS/x86_64/libssh2-dummy-*.rpm && \
    rm -rf /tmp/libssh2-dummy

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