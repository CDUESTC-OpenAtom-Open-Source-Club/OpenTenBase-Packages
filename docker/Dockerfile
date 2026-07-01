# OpenTenBase Docker Image
# 基于 OpenTenBase 5.0 RPM 包构建

FROM alpine:3.20 AS builder

# 安装编译工具
RUN apk add --no-cache curl rpm2cpio cpio

# 下载并解压 RPM 包
WORKDIR /build
RUN curl -fsSL https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/v5.0-p32/opentenbase-5.0-1.openeuler-22.03-5.0-x86_64.x86_64.rpm -o opentenbase.rpm \
    && rpm2cpio opentenbase.rpm | cpio -idmv

# 运行时镜像
FROM alpine:3.20

# 安装运行依赖
RUN apk add --no-cache \
    bash \
    libintl \
    libuuid \
    libxml2 \
    openssl \
    zlib

# 从 builder 复制 OpenTenBase
COPY --from=builder /build/usr/lib/opentenbase /usr/lib/opentenbase
COPY --from=builder /build/usr/bin /usr/bin

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