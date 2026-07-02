# OpenTenBase Docker Image
# RPM 包已自带 libssh2.so.1，无需额外处理

FROM rockylinux:9

# 安装运行依赖（curl-minimal 已在基础镜像中）
RUN yum install -y \
    gnupg2 \
    libatomic \
    libpq \
    && yum clean all

# 配置 OpenTenBase 仓库
RUN curl -fsSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh | bash

# 安装 OpenTenBase (RPM 包自带 libssh2.so.1)
RUN yum install -y opentenbase-5.0

# 创建数据目录
RUN mkdir -p /data/gtm /data/coord /data/dn1 && \
    chmod 755 /data

# 设置环境变量
ENV PATH="/usr/lib/opentenbase/5.0/bin:$PATH"
ENV LD_LIBRARY_PATH="/usr/lib/opentenbase/5.0/lib"

# 默认用户
USER root

WORKDIR /data

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pg_isready -h localhost -p 5432 || exit 1