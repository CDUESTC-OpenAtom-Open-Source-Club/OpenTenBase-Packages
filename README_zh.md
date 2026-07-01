# OpenTenBase Packages

[![GitHub Stars](https://img.shields.io/github/stars/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages?style=flat-square&logo=github&cacheSeconds=1800)](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/stargazers)
[![GitHub Downloads](https://img.shields.io/github/downloads/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/total?style=flat-square&logo=github&cacheSeconds=1800)](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases)
[![GitHub Release](https://img.shields.io/github/v/release/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages?style=flat-square&logo=github&cacheSeconds=1800)](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/latest)
[![License](https://img.shields.io/github/license/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages?style=flat-square&cacheSeconds=1800)](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/blob/main/LICENSE)

[English](README.md) | 中文

> **OpenTenBase 官方跨平台软件包仓库** — 为 OpenTenBase 分布式数据库提供企业级的多格式、多发行版打包与分发方案。

---

## 简介

**OpenTenBase Packages** 是 [OpenTenBase](https://github.com/OpenTenBase/OpenTenBase) 分布式数据库的官方打包与分发项目。我们为 Linux 主流发行版提供标准化的二进制软件包，支持 DEB（Debian/Ubuntu）与 RPM（RHEL/CentOS/Fedora）两大包管理体系，覆盖 x86_64 与 ARM64 架构。

**目标**：像 PostgreSQL 的 `apt.postgresql.org` 和 Docker 的 `download.docker.com` 一样，为 OpenTenBase 构建一套**长期维护、自动构建、多版本共存**的官方软件包仓库。

---

## 特性

| 特性 | 说明 |
|------|------|
| **多格式** | DEB (`.deb`) + RPM (`.rpm`) 双格式支持 |
| **多发行版** | Ubuntu/Debian，RHEL/CentOS/Fedora，Rocky/Alma，openEuler/EulerOS（含华为云 HCE 2.0，已端到端验证） |
| **多架构** | x86_64 (amd64) + ARM64 (aarch64) |
| **多版本共存** | 支持 v5.0 / v2.6 / v2.5 及开发版本并行安装，通过 `opentenbase-switch-version` 切换 |
| **一键安装** | `curl -sSL ... \| sudo bash` 自动检测系统、下载对应包、解决依赖 |
| **CI/CD 自动化** | GitHub Actions 自动构建、签名、发布 |
| **GPG 签名** | 所有发布包均经 GPG 签名（RSA 4096 位），确保包的完整性和来源可信 |
| **APT/RPM 仓库** | 官方仓库托管在 GitHub Pages — `apt install opentenbase` / `dnf install opentenbase` |
| **systemd 集成** | 原生 systemd 服务单元，支持 `systemctl` 管理 |
| **官方集群管理** | 内置官方 `opentenbase_ctl` C++ 二进制，通过 INI 配置文件管理集群全生命周期（install/start/stop/status/expand/shrink） |
| **Cloudflare CDN 加速** | 全球 CDN 加速镜像：`repo.blackevil217.com` |

---

## 快速安装

### 一键部署（推荐）

**白板机器 → 集群运行，一条命令搞定。** 支持交互式和非交互式：

```bash
# CDN 加速（推荐，全球加速）
curl -sSL https://repo.blackevil217.com/scripts/opentenbase.sh | sudo bash

# GitHub 直连（备用）
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/opentenbase.sh | sudo bash

# 非交互式（全自动，单节点默认值，适合 CI/自动化）
curl -sSL https://repo.blackevil217.com/scripts/opentenbase.sh | sudo bash -s -- install --yes

# 非交互式 + 自定义参数
sudo bash opentenbase.sh install --yes \
    --cluster-name mycluster \
    --ssh-password mypass123 \
    --gtm-ip 192.168.1.10
```

脚本自动完成：安装包 → 创建用户 → 配置 sshpass → 路径符号链接 → 生成 INI 配置 → `opentenbase_ctl install` → 启动验证

### 软件包仓库（手动安装）

#### APT（Ubuntu / Debian）

```bash
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash
sudo apt update && sudo apt install -y opentenbase
```

#### YUM/DNF（RHEL / CentOS / Fedora / openEuler / EulerOS）

```bash
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh | sudo bash
sudo dnf install -y opentenbase
```

安装包后，部署集群：

```bash
opentenbase_ctl install -c /tmp/otb_config.ini
opentenbase_ctl start -c /tmp/otb_config.ini
opentenbase_ctl status -c /tmp/otb_config.ini
```

> **openEuler / EulerOS（华为云）说明**：本仓库完整支持 openEuler 与华为云 EulerOS（HCE）2.0，
> 覆盖 aarch64 与 x86_64，已在 HCE 2.0 (aarch64) 上端到端验证通过。一键脚本在 EulerOS/openEuler 上会：
> - 自动安装 `sshpass`（EulerOS 仓库无此包，脚本从 CentOS Vault 下载 RPM 兜底）
> - 自动创建必需的 `opentenbase` 系统用户并配置 SSH 免密（home：`/var/lib/opentenbase`）
> - 自动预置本机 host key 到 `known_hosts`（`pgxc_ctl` 内部 SSH 需要）
> - **v5.0 自动改用 `pgxc_ctl` 启动**，绕过 `opentenbase_ctl` 端口分配 bug
>   （见 [Issue #215](https://github.com/OpenTenBase/OpenTenBase/issues/215)）
>
> 详见 [docs/EulerOS-Deployment-Issues.md](docs/EulerOS-Deployment-Issues.md)。

### 手动下载

```bash
# 从 Releases 下载: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases
# DEB: sudo apt install ./opentenbase_*.deb
# RPM: sudo dnf install ./opentenbase-*.rpm
```

### 卸载

```bash
# CDN 加速（推荐）
curl -sSL https://repo.blackevil217.com/scripts/uninstall.sh | sudo bash

# GitHub 直连（备用）
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/uninstall.sh | sudo bash

# 完全卸载（包括数据和日志，无需确认）
curl -sSL https://repo.blackevil217.com/scripts/uninstall.sh | sudo bash -s -- --purge --yes
```

---

## 国内镜像加速

安装脚本会自动检测并使用最快的可用镜像：

1. **Cloudflare CDN**（`repo.blackevil217.com/scripts/` 用于脚本，`repo.blackevil217.com/apt` 用于 APT，`repo.blackevil217.com/rpm` 用于 RPM）— 全球加速，永久免费
2. **GitHub Pages**（`cduestc-openatom-open-source-club.github.io/OpenTenBase-Packages/`）— 直接备用

> **推荐**：使用 `https://repo.blackevil217.com/scripts/opentenbase.sh` CDN 路径下载脚本，速度更快更稳定。

### 国内加速实测（2026-06-02）

**测试环境**: 华为云 EulerOS 2.0 aarch64（华东地区）

| 测试项 | Cloudflare CDN | GitHub Pages 直连 | 加速比 |
|--------|---------------|-------------------|--------|
| 下载 GPG Key | **0.6s** | 2m12s | **~200x** |
| 下载 Packages 索引 | **0.3s** | 45s | **~150x** |
| 下载 opentenbase-server RPM (5.5MB) | **1.2s** | 3m30s | **~175x** |

**结论**: Cloudflare CDN 在中国地区无需 VPN 即可使用，速度提升约 150-200 倍。脚本内置自动检测：优先尝试 CDN，超时后自动回退 GitHub Pages。

### 国内安装验证（EulerOS 2.0 aarch64）

| 测试项 | 结果 | 说明 |
|--------|------|------|
| `setup-rpm.sh` 执行 | ✅ | 自动选择 CDN 镜像 |
| `dnf install opentenbase` | ✅ | 从 CDN 仓库安装成功 |
| 已安装版本 | ✅ | v5.0, v2.6.0, v2.5.0 并存 |
| 版本切换 | ✅ | `opentenbase-switch-version` 正常 |
| 集群启动 | ✅ | GTM + Coordinator + Datanode 正常 |

---

## 系统要求

| 资源 | 最低要求 | 推荐配置 | 说明 |
|------|----------|----------|------|
| **内存** | 4 GB | 4 GB+ | OpenTenBase Coordinator 需要 ~4GB 共享内存（SPM 缓存 + 连接池 + workfile 管理器）。这是硬性要求，无法通过参数调优降低。 |
| **磁盘** | 2 GB | 10 GB+ | 二进制包（~500MB）+ 数据目录 |
| **CPU** | 1 核 | 2+ 核 | GTM 线程数根据 CPU 核心数自动检测 |
| **操作系统** | Ubuntu 20.04+, Debian 11+, RHEL 8+, Fedora 40+ | 见下方平台矩阵 | |

> **重要说明**：
> - **2GB 服务器无法运行 OpenTenBase** — Coordinator 共享内存需求（~4GB）超出可用资源。包括 2GB 的 Cloud Studio 容器。
> - **容器环境（Docker/K8s）**有硬性 cgroup 内存限制且无法添加 swap，请使用 4GB+ 容器。
> - 安装脚本会自动检测内存和容器环境，不满足要求时会中止并给出明确提示。
> - 真实 VM 环境 3-4GB 内存时，脚本可自动添加 swap 补充内存。

---

## 软件包清单

| 软件包 | 格式 | 描述 |
|--------|------|------|
| `opentenbase` | DEB / RPM | 元包，依赖 server + client |
| `opentenbase-server` | DEB / RPM | 服务端二进制（postgres, gtm, pg_ctl）+ 服务驱动 + 集群管理脚本 |
| `opentenbase-client` | DEB / RPM | 客户端工具（psql, pg_dump, pg_restore 等） |
| `opentenbase-contrib` | DEB / RPM | 扩展组件（pgbench, pg_stat_statements, postgres_fdw 等） |
| `libopentenbase-dev` | DEB / RPM | 开发头文件 + 静态库 + pg_config |
| `opentenbase-doc` | DEB / RPM | 文档 |

---

## 平台支持矩阵

| 发行版 | 版本 | DEB | RPM | x86_64 | aarch64 | 状态 |
|--------|------|:---:|:---:|:------:|:------:|------|
| Ubuntu | 20.04 (Focal) | ✅ | — | ✅ | ✅ | 已验证 |
| Ubuntu | 22.04 (Jammy) | ✅ | — | ✅ | ✅ | 已验证 |
| Ubuntu | 24.04 (Noble) | ✅ | — | ✅ | ✅ | 已验证 |
| Ubuntu | 25.04 (Plucky) | ✅ | — | ✅ | — | 已验证 |
| Debian | 11 (Bullseye) | ✅ | — | ✅ | ✅ | 已验证 |
| Debian | 12 (Bookworm) | ✅ | — | ✅ | ✅ | 已验证 |
| Debian | 13 (Trixie) | ✅ | — | ✅ | — | 已验证 |
| CentOS Stream | 8 / 9 | — | ✅ | ✅ | — | 已验证 |
| Rocky Linux | 8 / 9 | — | ✅ | ✅ | ✅ (仅 el9) | 已验证 |
| AlmaLinux | 8 / 9 | — | ✅ | ✅ | ✅ (仅 el9) | 已验证 |
| Fedora | 40 | — | ✅ | ✅ | — | 已验证 |
| OpenEuler | 22.03 | — | ✅ | ✅ | ✅ | 已验证 |

> **aarch64 说明**: RPM aarch64 包支持 el9（Rocky/Alma 9）和 openEuler 22.03。当 aarch64 仓库不存在时（el8、fedora），安装脚本会自动回退到 x86_64 仓库。DEB aarch64 全面支持所有发行版。

---

## 快速开始

```bash
# 1. 安装集群（GTM + Coordinator + Datanode）——需要 -c 指定拓扑配置
opentenbase_ctl install -c /tmp/otb_config.ini

# 2. 启动集群（安装后集群状态已持久化，无需 -c）
opentenbase_ctl start

# 3. 查看集群状态
opentenbase_ctl status

# 4. 连接数据库
opentenbase-psql -h 127.0.0.1 -p 11003 -U opentenbase -d postgres

# 5. 停止集群
opentenbase_ctl stop
```

> **版本链路说明**：`5.0` 使用官方 `opentenbase_ctl` + INI 配置；`2.5/2.6` 使用 `pgxc_ctl` + `pgxc_ctl.conf` 正式链路。

### Docker Compose 部署

使用 Docker Compose 一键部署完整的 OpenTenBase 集群（GTM + Coordinator + 2 个 Datanode）：

```bash
# 下载部署脚本
curl -sLO https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/docker/test-docker.sh
bash test-docker.sh

# 启动集群
cd /tmp/otb-docker/compose
docker compose up -d --build

# 连接数据库
docker compose exec coordinator psql -h 127.0.0.1 -U opentenbase -d postgres

# 停止集群
docker compose down -v
```

> **中国大陆用户注意**：由于 Docker Hub 在国内无法直接访问，需要配置 Docker 镜像加速器。编辑 `/etc/docker/daemon.json`：
>
> ```json
> {
>   "registry-mirrors": ["https://docker.m.daocloud.io"]
> }
> ```
>
> 然后重启 Docker：`sudo systemctl restart docker`
>
> 常用镜像加速器：
> - DaoCloud: `https://docker.m.daocloud.io`
> - 腾讯云: `https://mirror.ccs.tencentyun.com`
> - 华为云: `https://repo.huaweicloud.com`

### 多版本管理

OpenTenBase 支持多个版本并行安装，类似 PostgreSQL 的 `postgresql-14`、`postgresql-15` 管理方式。每个版本拥有独立的目录树。

```bash
# 查看已安装版本
opentenbase-switch-version

# 切换到指定版本（需目标版本已安装）
opentenbase-switch-version 5.0

# 切换到另一个版本
opentenbase-switch-version 2.6.0

# 验证当前版本
readlink /etc/opentenbase/current
```

**一键脚本切换版本：**

```bash
# 通过 CDN 一键脚本切换版本（需目标版本已安装）
curl -sSL https://repo.blackevil217.com/scripts/opentenbase.sh | sudo bash -s -- switch 5.0

# 或使用 GitHub 直连
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/opentenbase.sh | sudo bash -s -- switch 2.6.0
```

> **注意**：切换版本前需先停止当前版本的集群。多版本共存时，软件包注册只显示最后安装版本，但版本目录和集群进程会保留。详见"已知限制"部分。

**版本化目录结构：**

| 路径 | 用途 |
|------|------|
| `/usr/lib/opentenbase/<version>/` | 各版本的二进制文件和库 |
| `/etc/opentenbase/<version>/` | 各版本的配置文件 |
| `/var/lib/opentenbase/<version>/` | 各版本的数据目录 |
| `/var/log/opentenbase/<version>/` | 各版本的日志 |
| `/etc/opentenbase/current` | 指向当前活跃版本的符号链接 |

**支持的版本：** `5.0`（稳定版）、`2.6.0`、`2.5.0`（历史版本）、`master-{sha}`（开发版）、`latest`（别名）

---

## 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                    OpenTenBase Packages                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌───────────────┐   ┌───────────────┐   ┌──────────────┐     │
│   │  DEB Packages │   │  RPM Packages │   │   Docker     │     │
│   │  Ubuntu/Debian│   │  RHEL/CentOS  │   │   Images     │     │
│   │  (14 targets) │   │  (14 targets) │   │              │     │
│   └───────┬───────┘   └───────┬───────┘   └──────┬───────┘     │
│           │                   │                   │             │
│           └───────────────────┼───────────────────┘             │
│                               │                                 │
│                     ┌─────────▼─────────┐                       │
│                     │   GPG 签名验证     │                       │
│                     └─────────┬─────────┘                       │
│                               │                                 │
│                     ┌─────────▼─────────┐                       │
│                     │   版本管理器       │                       │
│                     │   v5.0 / v2.6 / … │                       │
│                     └─────────┬─────────┘                       │
│                               │                                 │
│                     ┌─────────▼─────────┐                       │
│                     │   GitHub Actions  │                       │
│                     │   自动构建 & 发布  │                       │
│                     └───────────────────┘                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 安装路径

| 路径 | 用途 |
|------|------|
| `/usr/lib/opentenbase/<version>/` | 二进制文件与库（与系统 PostgreSQL 隔离） |
| `/etc/opentenbase/<version>/` | 配置文件 |
| `/var/lib/opentenbase/<version>/` | 数据目录 |
| `/var/log/opentenbase/<version>/` | 日志目录 |
| `/usr/bin/opentenbase-ctl` | 集群管理二进制（符号链接 → 官方 `opentenbase_ctl`） |

---

## 部署方式

| 方面 | 预编译包 |
|------|---------|
| **部署时间** | ~2 分钟 |
| **镜像大小** | ~500 MB |
| **适用场景** | 生产环境、快速测试、评估 |

> 如需从源码构建，请参考 [source-build-guide.md](docs/source-build-guide.md)。

---

## 目录结构

```
OpenTenBase-Packages/
├── README.md                # 英文文档
├── README_zh.md             # 中文文档
├── CHANGELOG.md             # 发布历史
├── TEST-PLAN.md             # 测试矩阵与结果
├── config/                  # 配置模板
├── debian/                  # DEB 打包规则
├── rpm/                     # RPM 打包规则
├── docker/                  # Docker 构建环境
├── scripts/                 # 构建、发布、安装脚本
├── patches/                 # 源码补丁
├── test/                    # 自动化测试
│   └── advanced/            # 高级测试套件
└── docs/                    # 文档与教程
    ├── QUICKSTART.md        # 快速开始指南
    ├── CONTRIBUTING.md      # 贡献指南
    ├── source-build-guide.md # 源码构建指南
    ├── 01-quickstart.md     # 教程：快速开始
    ├── 02-basic-ops.md      # 教程：基本操作
    ├── 03-architecture.md   # 教程：架构
    ├── 04-advanced.md       # 教程：高级用法
    ├── 05-troubleshoot.md   # 教程：故障排除
    ├── 06-best-practices.md # 教程：最佳实践
    ├── 07-deployment.md     # 教程：部署
    └── archive/             # 已归档的规划文档
```

---

## 发布历史

| 版本 | 日期 | 资产数 | 说明 |
|------|------|--------|------|
| v5.0-p32 | 2026-06-29 | 156 | GTM ≤2核修复（全局 `noaffinity.so` 注入）+ CN 端口 11003 + 一键部署脚本端到端验证 + DEB 构建修复 |
| v5.0-p31 | 2026-06-28 | 156 | 官方 `opentenbase_ctl` C++ 二进制，CLI11/libpqxx 打包 |
| v5.0-p11 | 2026-06-02 | 156 | Cloudflare CDN 加速文档 |
| v5.0-p10 | 2026-06-02 | 156 | ARM64 原生构建 + Docker E2E + 版本切换修复 |
| v5.0-p9 | 2026-06-01 | 150 | 多版本端到端验证（ARM64 实机） |
| v5.0-p8 | 2026-06-01 | 150 | 压力测试（7/7）、跨机器部署、dh_install 修复 |
| v5.0-p4 | 2026-05-30 | 150 | 高级测试套件（31/31），14 个发行版 |
| v5.0-p3 | 2026-05-29 | 150 | 多版本（5.0+2.6.0+2.5.0），15 个发行版 |
| v5.0-p2 | 2026-05-28 | 50 | 修复 lib/postgresql 路径，覆盖 15 个发行版 |
| v5.0 | 2026-05-18 | 7 | 首次发布 |

详见 [GitHub Releases](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases)。

---

## 路线图

**愿景**：为 OpenTenBase 构建一套长期维护、自动构建、多版本共存的官方软件包仓库，像 PostgreSQL 的 `apt.postgresql.org` 和 Docker 的 `download.docker.com` 一样。

### 阶段一：基础打牢（1-2 周）-- 已完成

- [x] 所有目标发行版的 Docker 构建环境
- [x] CI 工作流：30 个构建目标（16 DEB + 14 RPM）
- [x] x86_64 + aarch64 双架构支持
- [x] 多版本共存（版本化路径 + 符号链接切换）
- [x] 自动发布流水线（tag 触发构建 + 测试 + 发布）

### 阶段二：官方 APT 仓库（1-2 月）-- 已完成

- [x] 多版本管理（`opentenbase-switch-version`）
- [x] 一键安装脚本
- [x] GPG 签名集成（RSA 4096 位，CI 自动化）
- [x] APT/RPM 仓库托管（GitHub Pages，免费）

### 阶段三：跨平台生态（3-6 月）

- [x] RPM 包支持（RHEL/CentOS/Rocky/Fedora/openEuler）
- [x] 自动化 CI/CD 流水线
- [ ] 打包规范化
- [ ] 代码质量审查和上游贡献

### 完整发行版支持矩阵

#### DEB 包（16 个构建目标）

| 发行版 | 版本 | Codename | x86_64 | aarch64 |
|--------|------|----------|--------|---------|
| Ubuntu | 18.04 | bionic | ✅ | - |
| Ubuntu | 18.10 | cosmic | ✅ | - |
| Ubuntu | 19.04 | disco | ✅ | - |
| Ubuntu | 19.10 | eoan | ✅ | - |
| Ubuntu | 20.04 | focal | ✅ | ✅ |
| Ubuntu | 22.04 | jammy | ✅ | ✅ |
| Ubuntu | 22.10 | kinetic | ✅ | - |
| Ubuntu | 23.10 | mantic | ✅ | - |
| Ubuntu | 24.04 | noble | ✅ | ✅ |
| Ubuntu | 24.10 | oracular | ✅ | - |
| Ubuntu | 25.04 | plucky | ✅ | ✅ |
| Debian | 9 | stretch | ✅ | - |
| Debian | 10 | buster | ✅ | - |
| Debian | 11 | bullseye | ✅ | ✅ |
| Debian | 12 | bookworm | ✅ | ✅ |
| Debian | 13 | trixie | ✅ | ✅ |

#### RPM 包（14 个构建目标）

| 发行版 | 版本 | x86_64 | aarch64 |
|--------|------|--------|---------|
| CentOS Stream | 8 | ✅ | - |
| CentOS Stream | 9 | ✅ | ✅ |
| Rocky Linux | 8 | ✅ | - |
| Rocky Linux | 9 | ✅ | ✅ |
| AlmaLinux | 8 | ✅ | - |
| AlmaLinux | 9 | ✅ | ✅ |
| Fedora | 40 | ✅ | ✅ |
| OpenEuler | 22.03 | ✅ | ✅ |

**总计**：30 个构建目标，覆盖 15+ 发行版，支持 x86_64 + aarch64 双架构。

---

## 测试

所有 15 个发行版均通过 CI 验证（安装 + 集群 + SQL + 高级测试）。

### 测试套件（共 38 项测试）

| 套件 | 测试数 | 内容 |
|------|--------|------|
| 基础 SQL | 1 | CREATE TABLE, INSERT, SELECT |
| 事务测试 | 6 | COMMIT/ROLLBACK、隔离级别、SAVEPOINT |
| 连接池 | 6 | 并发连接、池耗尽、重载 |
| 数据类型 | 7 | int, text, jsonb, timestamp, array |
| 性能基准 | 6 | 批量 INSERT、JOIN、索引效果 |
| 故障恢复 | 7 | 集群健康、压力读写、数据一致性 |
| 压力测试 | 7 | 100 行 INSERT、批量 UPDATE/DELETE、聚合查询 |

### 跨机器部署

已在真实硬件上验证：devenv（ARM64, GTM+Coordinator）+ 47.108（x86_64, Datanode），通过 SSH 反向隧道连接。

```bash
# 运行跨机器测试
./test/cross-machine-test.sh

# 在 CI 中触发压力测试
gh workflow run stress-test.yml
```

---

## 已知限制

| 限制 | 说明 |
|------|------|
| 多版本软件包注册 | 所有版本共享同一包名 `opentenbase`，后安装的版本会覆盖前一版本的软件包注册（`rpm -q` 或 `dpkg -l` 只显示最后安装版本）。但版本目录 `/usr/lib/opentenbase/<ver>` 会保留，集群进程仍可正常运行。 |
| 多版本配置目录 | 安装新版本时，前一版本的 `/etc/opentenbase/<ver>` 配置目录会被覆盖，导致 `opentenbase-switch-version` 可能无法切换到旧版本（需重装）。 |
| 多版本 bin 目录 | 安装新版本时，前一版本的 `/usr/lib/opentenbase/<ver>/bin` 目录可能被删除，导致无法使用旧版本的工具（如 `pgxc_ctl`），但旧版本集群进程仍可继续运行。 |

---

## 故障排查

### `Unable to locate package opentenbase`

**原因**：APT 源未更新或仓库未签名导致 `apt update` 跳过了 OpenTenBase 源。

**解决**：

```bash
# 1. 重新运行安装脚本（会自动检测签名状态）
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash

# 2. 手动更新
sudo apt update
sudo apt install opentenbase
```

### `The repository '... noble Release' is not signed`

**原因**：仓库缺少 GPG 签名文件（`Release.gpg` / `InRelease`）。脚本会自动回退到 `trusted=yes` 模式，无需手动处理。如果仍然报错，重新运行安装脚本即可。

### `GPG 密钥下载失败`

**原因**：网络环境无法访问 Cloudflare CDN 或 GitHub Pages。

**解决**：

```bash
# 方法1：重试（网络波动可能导致临时失败）
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash

# 方法2：手动下载密钥并配置
curl -sSL https://repo.blackevil217.com/apt/gpg-key.asc -o /tmp/key.asc
sudo gpg --batch --dearmor -o /usr/share/keyrings/opentenbase-archive-keyring.gpg < /tmp/key.asc

# 方法3：配置环境变量使用代理
export https_proxy=http://your-proxy:port
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash
```

### `apt-get update` 报其他仓库 404 错误

**原因**：系统其他第三方源失效（如 `dl.modular.com`），与 OpenTenBase 无关。

**解决**：检查 `/etc/apt/sources.list.d/` 下的其他源文件，移除或禁用失效的源。

### 安装后 `opentenbase-ctl: command not found`

**原因**：安装未完成或 PATH 未包含 `/usr/bin`。

**解决**：

```bash
# 检查是否安装成功
dpkg -l | grep opentenbase

# 重新安装
sudo apt install --reinstall opentenbase

# 检查文件是否存在（符号链接指向官方 opentenbase_ctl）
ls -la /usr/bin/opentenbase-ctl
ls -la /usr/lib/opentenbase/5.0/bin/opentenbase_ctl
```

### `error while loading shared libraries: libpqxx-6.4.so`

**原因**：缺少 `libpqxx` 运行时库。v5.0-p30 起已将此库打包到软件包中。

**解决**：

```bash
# 检查库文件是否存在
ls -la /usr/lib/opentenbase/5.0/lib/libpqxx*

# 如果缺失，安装系统包或升级到 v5.0-p31+
sudo apt install -y libpqxx-dev  # DEB 系
sudo dnf install -y libpqxx-devel  # RPM 系
```

---

## 贡献

欢迎贡献代码、报告问题或提出改进建议！

1. Fork 本仓库
2. 创建特性分支：`git checkout -b feature/your-feature`
3. 提交更改并推送
4. 创建 Pull Request

详见 [贡献指南](docs/CONTRIBUTING.md)。

---

## 许可证

与 OpenTenBase 相同 — [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)。

---

## 相关链接

| 资源 | 链接 |
|------|------|
| **本项目** | https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages |
| **上游仓库** | https://github.com/OpenTenBase/OpenTenBase |
| **OpenTenBase 文档** | https://github.com/OpenTenBase/OpenTenBase/wiki |
| **问题反馈** | [Issues](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/issues) |

---

## 数据统计

[![Star History Chart](https://api.star-history.com/svg?repos=CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages&type=Date)](https://star-history.com/#CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages&Date)

---

**维护者**：muzimu217
**最后更新**：2026-06-29（v5.0-p32，GTM 2核修复 + CN 端口 11003）
