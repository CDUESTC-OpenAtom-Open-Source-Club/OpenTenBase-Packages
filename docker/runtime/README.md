# OpenTenBase 运行时镜像（直装版）

本目录提供 **多发行版成品运行时镜像**，通过包管理器（apt/dnf）直接安装 GitHub Releases 的成品包。
镜像内置 `entrypoint.sh`，支持单节点启动，也可配合 `docker/compose/` 多节点编排部署 GTM + Coordinator + Datanode 集群。

## 可用镜像

### DEB 发行版（APT 直装）

| Dockerfile | 基础镜像 | 架构 |
|------------|----------|------|
| `Dockerfile.ubuntu-20.04` | ubuntu:20.04 (focal) | amd64 + arm64 |
| `Dockerfile.ubuntu-22.04` | ubuntu:22.04 (jammy) | amd64 + arm64 |
| `Dockerfile.ubuntu-24.04` | ubuntu:24.04 (noble) | amd64 + arm64 |
| `Dockerfile.ubuntu-25.04` | ubuntu:25.04 (plucky) | amd64 + arm64 |
| `Dockerfile.debian-11` | debian:11 (bullseye) | amd64 + arm64 |
| `Dockerfile.debian-12` | debian:12 (bookworm) | amd64 + arm64 |
| `Dockerfile.debian-13` | debian:13 (trixie) | amd64 + arm64 |

### RPM 发行版（DNF 直装）

| Dockerfile | 基础镜像 | 架构 |
|------------|----------|------|
| `Dockerfile.rockylinux-8` | rockylinux:8 | amd64 + arm64 |
| `Dockerfile.rockylinux-9` | rockylinux:9 | amd64 + arm64 |
| `Dockerfile.almalinux-8` | almalinux:8 | amd64 + arm64 |
| `Dockerfile.almalinux-9` | almalinux:9 | amd64 + arm64 |
| `Dockerfile.fedora-40` | fedora:40 | amd64 + arm64 |
| `Dockerfile.openeuler-22.03` | openeuler/openeuler:22.03 | amd64 + arm64 |
| `Dockerfile.openeuler-24.03` | quay.io/openeuler/openeuler:24.03-lts | amd64 + arm64 |

### 离线解包版（无网络依赖）

| Dockerfile | 基础镜像 | 说明 |
|------------|----------|------|
| `Dockerfile.runtime` | openeuler/openeuler:22.03 | rpm2cpio 解包，无网络仓库依赖 |

> **推荐**：直装版（APT/DNF）构建更快、镜像更小、版本可随仓库自动更新。
> 离线版适用于无网络环境或特殊部署场景。

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
