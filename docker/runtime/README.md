# OpenTenBase 运行时镜像（直装版）

本目录提供 **多发行版成品运行时镜像**，通过包管理器（apt/dnf）直接安装 GitHub Releases 的成品包。
镜像内置 `entrypoint.sh`，支持单节点启动，也可配合 `docker/compose/` 多节点编排部署 GTM + Coordinator + Datanode 集群。

## 可用镜像

| Dockerfile | 基础镜像 | 包管理器 | 架构 |
|------------|----------|----------|------|
| `Dockerfile.ubuntu-24.04` | ubuntu:24.04 | apt | amd64 + arm64 |
| `Dockerfile.debian-12` | debian:bookworm | apt | amd64 + arm64 |
| `Dockerfile.rockylinux-9` | rockylinux:9 | dnf | amd64 + arm64 |
| `Dockerfile.openeuler-22.03` | openeuler/openeuler:22.03 | dnf | amd64 + arm64 |
| `Dockerfile.runtime` | openeuler/openeuler:22.03 | rpm2cpio 解包（离线版） | 见文件 |

> `Dockerfile.runtime` 是早期的 **离线解包版**（不依赖网络仓库，把 RPM 解压进镜像）。
> 新场景推荐使用上表 4 个**直装版**，构建更快、镜像更小、版本可随仓库更新。

## 构建

```bash
# 单架构（当前主机架构）
docker build -f docker/runtime/Dockerfile.rockylinux-9 -t opentenbase:5.0-rocky9 .

# 多架构（需 buildx）
docker buildx build --platform linux/amd64,linux/arm64 \
    -f docker/runtime/Dockerfile.debian-12 -t opentenbase:5.0-debian12 --push .
```

构建时可指定版本（默认 5.0）：

```bash
docker build --build-arg OTB_VERSION=5.0 -f docker/runtime/Dockerfile.ubuntu-24.04 -t opentenbase:5.0-ubuntu24.04 .
```

## 运行

### 单节点（仅 Coordinator，体验用）

```bash
docker run -d --name otb \
    -p 5432:5432 \
    -e NODE_TYPE=coordinator \
    -e NODE_NAME=coordinator \
    -e GTM_HOST=127.0.0.1 \
    -e COORD_HOST=127.0.0.1 \
    opentenbase:5.0-rocky9
```

> 单节点模式下 Coordinator 仍需连接 GTM。完整集群请用下面的 Compose 编排。

### 多节点集群（GTM + Coordinator + Datanode×2）

参见 `docker/compose/docker-compose.yml`，将其中的 `build:` 指向本目录任一 Dockerfile 即可切换发行版：

```yaml
services:
  gtm:
    build:
      context: ../..
      dockerfile: docker/runtime/Dockerfile.ubuntu-24.04
    environment:
      NODE_TYPE: gtm
      NODE_NAME: gtm
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `NODE_TYPE` | （必填） | `gtm` / `coordinator` / `datanode` |
| `NODE_NAME` | （必填） | 节点名，如 `gtm`、`coordinator`、`datanode1` |
| `GTM_HOST` | `gtm` | GTM 主机名 |
| `GTM_PORT` | `6666` | GTM 端口 |
| `COORD_HOST` | `coordinator` | Coordinator 主机名 |
| `COORD_PORT` | `5432` | Coordinator 端口 |
| `DN_PORT` | `15432` | Datanode 端口 |
| `DN_FORWARD_PORT` | `6670` | Datanode forward 端口 |

## 数据卷

数据目录为 `/var/lib/opentenbase/data/${NODE_NAME}`，建议挂载持久卷：

```bash
docker run -v otb-data:/var/lib/opentenbase/data ...
```
