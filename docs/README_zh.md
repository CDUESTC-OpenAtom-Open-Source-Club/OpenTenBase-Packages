# OpenTenBase Packages

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
| **多发行版** | Ubuntu 20.04 / 22.04 / 24.04, Debian 11 / 12, RHEL/CentOS 8/9, Fedora, Rocky Linux, AlmaLinux, OpenEuler |
| **多架构** | x86_64 (amd64) + ARM64 (aarch64) |
| **多版本共存** | 支持 v5.0 / v2.6 / v2.5 及开发版本并行安装，通过 `opentenbase-ctl switch` 切换 |
| **一键安装** | `curl -sSL ... \| sudo bash` 自动检测系统、下载对应包、解决依赖 |
| **CI/CD 自动化** | GitHub Actions 自动构建、签名、发布 |
| **systemd 集成** | 原生 systemd 服务单元，支持 `systemctl` 管理 |
| **集群管理** | 内置 `opentenbase-ctl` 管理脚本，一键初始化、启动、停止集群 |

---

## 快速安装

### 一键安装（推荐）

```bash
curl -sLO https://github.com/muzimu217/OpenTenBase-packages/releases/latest/download/install.sh
sudo bash install.sh
```

安装脚本自动完成：
- 检测操作系统及版本
- 配置软件包仓库（APT / YUM）
- 下载并安装对应格式的软件包
- 解决依赖关系

### APT 手动安装（Debian / Ubuntu）

```bash
# 添加仓库
curl -sSL https://github.com/muzimu217/OpenTenBase-packages/releases/latest/download/setup-apt.sh | sudo bash

# 安装
sudo apt update
sudo apt install opentenbase
```

### YUM/DNF 手动安装（RHEL / CentOS / Fedora）

```bash
# 添加仓库
curl -sSL https://github.com/muzimu217/OpenTenBase-packages/releases/latest/download/setup-rpm.sh | sudo bash

# 安装
sudo dnf install opentenbase
```

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

| 发行版 | 版本 | DEB | RPM | x86_64 | ARM64 | 状态 |
|--------|------|:---:|:---:|:------:|:-----:|------|
| Ubuntu | 20.04 (Focal) | ✅ | — | ✅ | ✅ | 已验证 |
| Ubuntu | 22.04 (Jammy) | ✅ | — | ✅ | ✅ | 已验证 |
| Ubuntu | 24.04 (Noble) | ✅ | — | ✅ | ✅ | 已验证 |
| Debian | 11 (Bullseye) | ✅ | — | ✅ | ✅ | 已验证 |
| Debian | 12 (Bookworm) | ✅ | — | ✅ | ✅ | 已验证 |
| RHEL / CentOS | 8 | — | ✅ | ✅ | ✅ | 已验证 |
| RHEL / CentOS | 9 | — | ✅ | ✅ | ✅ | 已验证 |
| Rocky Linux | 8 / 9 | — | ✅ | ✅ | ✅ | 已验证 |
| AlmaLinux | 8 / 9 | — | ✅ | ✅ | ✅ | 已验证 |
| Fedora | 39+ | — | ✅ | ✅ | ✅ | 已验证 |
| OpenEuler | 22.03+ | — | ✅ | ✅ | ✅ | 已验证 |

---

## 快速开始

```bash
# 1. 初始化集群（GTM + Coordinator + Datanode）
opentenbase-ctl init

# 2. 启动集群
opentenbase-ctl start

# 3. 查看集群状态
opentenbase-ctl status

# 4. 连接数据库
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1

# 5. 停止集群
opentenbase-ctl stop
```

### 多版本管理

OpenTenBase 支持多个版本并行安装，类似 PostgreSQL 的 `postgresql-14`、`postgresql-15` 管理方式。每个版本拥有独立的目录树。

```bash
# 查看已安装版本
opentenbase-switch-version

# 切换到指定版本
opentenbase-switch-version 5.0

# 切换到另一个版本
opentenbase-switch-version 2.6.0

# 验证当前版本
readlink /etc/opentenbase/current
```

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
| `/usr/bin/opentenbase-ctl` | 集群管理脚本 |

---

## 部署方式

OpenTenBase 支持两种部署方式：

| 方面 | 预编译包 | 源码编译 |
|------|---------|---------|
| **部署时间** | ~2 分钟 | 30-60 分钟（首次） |
| **自定义** | 不支持 | 完全控制（调试、cassert 等） |
| **适用场景** | 生产环境、快速测试 | 开发、学习、贡献 |
| **镜像大小** | ~500 MB | ~2 GB |

**建议**：生产环境和快速体验使用预编译包，开发调试和贡献代码使用源码编译。详见 [source-build-guide.md](source-build-guide.md)。

---

## 从源码构建

### 使用 Docker 构建（推荐）

```bash
git clone https://github.com/muzimu217/OpenTenBase-packages.git
cd OpenTenBase-packages

# 构建所有发行版
./scripts/build-multi.sh --all

# 仅构建 Ubuntu 24.04
./scripts/build-multi.sh -d ubuntu -v 24.04

# 仅构建 RPM
./scripts/build-multi.sh --rpm
```

### 本地构建

```bash
# 安装构建依赖
sudo apt install -y debhelper-compat bison flex perl libreadline-dev \
    zlib1g-dev libssl-dev libxml2-dev libldap2-dev uuid-dev pkg-config

# 构建 DEB 包
./scripts/build-deb.sh

# 构建 RPM 包
./scripts/build-rpm.sh
```

---

## 目录结构

```
OpenTenBase-packages/
├── .github/workflows/       # CI/CD 流水线
├── config/                  # 默认配置模板
├── debian/                  # DEB 打包规则
├── rpm/                     # RPM 打包规则
├── docker/                  # Docker 构建环境
├── scripts/                 # 构建、发布、签名脚本
├── systemd/                 # systemd 服务单元
├── patches/                 # 源码补丁
├── test/                    # 自动化测试
└── docs/                    # 文档
```

---

## 发布历史

| 版本 | 日期 | 资产数 | 说明 |
|------|------|--------|------|
| v5.0-multi9 | 2026-05-20 | 31 | 多发行版发布（DEB + RPM） |
| v5.0-multi8 | 2026-05-18 | 13 | 扩展发行版支持 |
| v5.0-1ubuntu1 | 2026-05-18 | 7 | 首个 DEB 发布 |
| v5.0 | 2026-05-18 | 7 | 首次发布 |

详见 [GitHub Releases](https://github.com/muzimu217/OpenTenBase-deb/releases)。

---

## 路线图

**愿景**：为 OpenTenBase 构建一套长期维护、自动构建、多版本共存的官方软件包仓库，像 PostgreSQL 的 `apt.postgresql.org` 和 Docker 的 `download.docker.com` 一样。

### 阶段一：基础打牢（1-2 周）-- 已完成

- [x] 所有目标发行版的 Docker 构建环境
- [x] CI 工作流：30 个构建目标（16 DEB + 14 RPM）
- [x] x86_64 + aarch64 双架构支持
- [x] 多版本共存（版本化路径 + 符号链接切换）
- [x] 自动发布流水线（tag 触发构建 + 测试 + 发布）

### 阶段二：官方 APT 仓库（1-2 月）-- 进行中

- [x] 多版本管理（`opentenbase-switch-version`）
- [x] 一键安装脚本
- [ ] GPG 签名集成
- [ ] APT/RPM 仓库托管（需要域名和服务器）

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

## 已知限制

| 限制 | 说明 |
|------|------|
| 同机多集群 | 由于端口冲突，不支持同一台机器运行多套集群；每台机器运行一套集群（GTM + 协调器 + 数据节点） |

---

## 贡献

欢迎贡献代码、报告问题或提出改进建议！

1. Fork 本仓库
2. 创建特性分支：`git checkout -b feature/your-feature`
3. 提交更改并推送
4. 创建 Pull Request

详见 [贡献指南](CONTRIBUTING.md)。

---

## 许可证

与 OpenTenBase 相同 — [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)。

---

## 相关链接

| 资源 | 链接 |
|------|------|
| **本项目** | https://github.com/muzimu217/OpenTenBase-packages |
| **上游仓库** | https://github.com/OpenTenBase/OpenTenBase |
| **OpenTenBase 文档** | https://github.com/OpenTenBase/OpenTenBase/wiki |
| **问题反馈** | [Issues](https://github.com/muzimu217/OpenTenBase-packages/issues) |

---

**维护者**：muzimu217
**最后更新**：2026-05-24
