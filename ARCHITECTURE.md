# OpenTenBase Packages — 仓库架构文档

> **一句话**：本仓库是打包配方仓库。成品安装包（.deb / .rpm）不在此 Git 里，而是由 CI 自动构建后推送到 [GitHub Releases](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases)（每个 Release 150-200+ 个文件），并通过 Cloudflare CDN（`repo.blackevil217.com`）全球分发。

---

## 目录

- [全景架构图](#全景架构图)
- [仓库目录逐项说明](#仓库目录逐项说明)
- [完整的安装包清单](#完整的安装包清单)
  - [支持的 OpenTenBase 版本](#支持的-opentenbase-版本)
  - [DEB 包完整矩阵 (逐行)](#deb-包完整矩阵)
  - [RPM 包完整矩阵 (逐行)](#rpm-包完整矩阵)
  - [覆盖率统计](#覆盖率统计)
  - [✅ 全覆盖 vs ⚠️ 部分覆盖 vs ❌ 无覆盖](#覆盖率可视化)
- [CI 构建流水线](#ci-构建流水线)
- [分发链路](#分发链路)
- [已知问题与缺口](#已知问题与缺口)
- [修复建议与路线图](#修复建议与路线图)

---

## 全景架构图

```
                         github.com/OpenTenBase/OpenTenBase
                         (上游源码，外部仓库)
                                  │
                    git clone --branch v5.0 / v2.6.0 / v2.5.0
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  本仓库 (Git Repo)                                                       │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ 打包配方层                                                        │   │
│  │                                                                   │   │
│  │  debian/              rpm/               patches/                │   │
│  │  ├─ control (6子包)   ├─ opentenbase.spec  ├─ 01-bool-stdbool    │   │
│  │  ├─ rules (13KB)      ├─ build-rpm.sh      ├─ 02-nolic-sharding  │   │
│  │  ├─ *.install         ├─ libssh2-1.11.1    ├─ 03-atomic128-x86   │   │
│  │  ├─ *.postinst/prerm  └─ README.md         ├─ 04-gtm-thread-bind │   │
│  │  └─ *.lintian-overrides                  └─ series             │   │
│  │                                                                   │   │
│  │  config/              scripts/             systemd/               │   │
│  │  ├─ *.conf.template   ├─ opentenbase.sh    ├─ .service            │   │
│  │  ├─ v2.5.0/           ├─ setup-apt.sh      └─ .tmpfiles           │   │
│  │  ├─ v2.6.0/           ├─ setup-rpm.sh                             │   │
│  │  ├─ v5.0/             ├─ switch-version.sh                        │   │
│  │  └─ lowmem/           ├─ uninstall.sh                             │   │
│  │                        ├─ tools/ (内部构建工具)                     │   │
│  │                        └─ extras/                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ 容器化层                                                          │   │
│  │                                                                   │   │
│  │  docker/                                                          │   │
│  │  ├─ Dockerfile         → 通用镜像 (Rocky 9, dnf安装)               │   │
│  │  ├─ docker-compose.yml → 用户快速编排                              │   │
│  │  ├─ test-docker.sh     → E2E 测试入口                              │   │
│  │  ├─ README.md          → Docker 使用说明                           │   │
│  │  ├─ build/    → 7 个发行版构建容器 (Dockerfile ×7)                │   │
│  │  ├─ cluster/  → 分布式集群部署 (CentOS + 源码编译)                  │   │
│  │  ├─ compose/  → 多节点 Compose 编排 (GTM+CN+DN×2)                 │   │
│  │  ├─ dev/      → 开发环境 (ubuntu:24.04 + gcc-12)                  │   │
│  │  └─ runtime/  → 运行时镜像 (openEuler 22.03)                      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ 测试与文档                                                         │   │
│  │                                                                   │   │
│  │  test/                 docs/                   binaries/          │   │
│  │  ├─ smoke-test.sh     ├─ 01~07 渐进教程      ├─ sshpass-x86_64   │   │
│  │  ├─ multi-node-test   ├─ CONTRIBUTING 中英    ├─ sshpass-aarch64  │   │
│  │  ├─ version-switch    ├─ EulerOS 专项         └─ README.md (免责) │   │
│  │  ├─ docker-e2e        ├─ archive/ (历史)        ⚠️ 无安装包      │   │
│  │  └─ advanced/ (5项)   └─ diagrams/ (架构图)                       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ CI/CD 层 (10 个 Workflow)                                         │   │
│  │                                                                   │   │
│  │  .github/workflows/                                               │   │
│  │  ├─ build-deb.yml (17KB) ← DEB 主力: amd64 21job + arm64 10job   │   │
│  │  ├─ build-rpm.yml (18KB) ← RPM 主力: x86_64 24job + aarch64 9job │   │
│  │  ├─ build-multi.yml (9KB) ← 辅助: DEB 7发行版 v5.0 only          │   │
│  │  ├─ release.yml    ← 聚合产物 → GPG签名 → 创建 GitHub Release     │   │
│  │  ├─ deploy-repo.yml ← 发布后 → GitHub Pages + CDN 同步            │   │
│  │  ├─ test.yml / test-all.yml / stress-test.yml  ← 三层测试         │   │
│  │  ├─ build-sshpass.yml ← 静态 sshpass 编译                         │   │
│  │  └─ docker-publish.yml ← GHCR 镜像推送                            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────┬──────────────────────────────────────┘
                                   │  git push / tag / workflow_dispatch
                                   ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  GitHub Actions — 自动化构建                                              │
│                                                                          │
│  build-deb.yml                     build-rpm.yml                         │
│  ┌─────────────────────────────┐  ┌─────────────────────────────┐       │
│  │ amd64: 7distro×3ver×6子包   │  │ x86_64: 8distro×3ver×~6子包 │       │
│  │  = ~126 个 .deb             │  │  = ~144 个 .rpm              │       │
│  │                             │  │                             │       │
│  │ arm64: 10combo×6子包        │  │ aarch64: 9combo×~6子包       │       │
│  │  = ~60 个 .deb              │  │  = ~54 个 .rpm               │       │
│  └─────────────┬───────────────┘  └─────────────┬───────────────┘       │
│                │                                │                        │
│                └──────────────┬─────────────────┘                        │
│                               ▼                                          │
│                    release.yml (聚合 → 签名 → 创建 Release)               │
│                               │                                          │
│              ┌────────────────┼────────────────┐                         │
│              ▼                ▼                ▼                          │
│     GitHub Releases    GitHub Pages      Cloudflare CDN                  │
│     v5.0-p32: 203文件   APT/RPM 仓库      repo.blackevil217.com          │
│     直接下载            标准包管理         国内 150-200x 加速              │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 仓库目录逐项说明

### `debian/` — DEB 打包配方 (⭐ 全仓库最规范)

定义了 **6 个子包**：

| 子包 | 内容 | 大小 |
|------|------|------|
| `opentenbase` | 元包（纯依赖聚合，无文件） | 极小 |
| `opentenbase-server` | postgres, gtm, gtm_proxy, pg_ctl, initdb, opentenbase_ctl | ~500MB |
| `opentenbase-client` | psql, pg_dump, pg_restore, libpq.so | ~50MB |
| `opentenbase-contrib` | pg_stat_statements, postgres_fdw, pgbench 等扩展 | ~30MB |
| `libopentenbase-dev` | C 头文件, pg_config, 静态库 | ~20MB |
| `opentenbase-doc` | HTML 手册, man pages | ~10MB |

每个子包有独立的 `.install` (安装清单) + `.links` (符号链接) + 维护脚本 (postinst/prerm/postrm)。

### `rpm/` — RPM 打包配方 (⭐ 单 SPEC + 条件宏)

单一 SPEC 文件通过条件宏适配不同发行版：
- `%if 0%{?rhel} == 8` → gcc-toolset-11 (C++17)
- `%if 0%{?fedora}` → 最新工具链
- RHEL-9 自动启用 CRB repo

子包拆分与 DEB 一致（6 个子包）。

### `docker/` — 容器化 (⭐ 5 场景 + 2 入口)

| 位置 | 用途 | 内容 | 用户可用？ |
|------|------|------|:---:|
| `Dockerfile` (根) | 通用安装镜像 | Rocky 9 + dnf install opentenbase | ✅ 可运行 |
| `docker-compose.yml` (根) | 用户快速编排 | 单命令启动集群 | ✅ 可运行 |
| `build/` | 构建容器 (供 CI) | **7 Dockerfile** | ❌ 仅编译用 |
| `cluster/` | 源码编译 + 集群部署 | CentOS + docker-compose.source.yml | ⚠️ 需手动编译 |
| `compose/` | 多节点 Compose 编排 | 生产级 GTM+CN+DN×2 | ✅ 可运行 |
| `dev/` | 二次开发环境 (⭐) | ubuntu:24.04 + gcc-12 + ccache + docker-compose.dev.yml | 🛠️ 二次编译 |
| `runtime/` | 运行时镜像 (直装版 ×4 + 解包版 ×1) | ubuntu24.04/debian12/rocky9/openeuler22.03 + entrypoint | ✅ 可运行 |
| `test-docker.sh` | Docker E2E 测试入口 | 自动化测试 | — |
| `README.md` | Docker 使用文档 | 快速开始 + 故障排查 | — |

> ✅ **Docker 运行时镜像已多发行版化**（2026-07-02）：用户可直接 `docker run` 的成品运行时镜像从 2 个（Rocky 9 + openEuler 22.03）扩展到 **6 个**（新增 Ubuntu 24.04、Debian 12 直装版 + openEuler 22.03 直装版）。每个镜像均通过 apt/dnf 仓库直装，支持多架构（amd64+arm64）。详见 `docker/runtime/README.md`。

> 🛠️ **二次编译（源码编译）已完整支持** — 面向二次开发者的两套 Docker Compose 方案：
> 
> | 文件 | 适合场景 | 编译速度 | 命令 |
> |------|---------|---------|------|
> | `docker/dev/docker-compose.dev.yml` | 日常迭代开发 (推荐) | 快（ccache加速，增量只需几十秒） | `OTB_SRC_DIR=/path/to/source docker compose -f docker/dev/docker-compose.dev.yml up` |
> | `docker/cluster/docker-compose.source.yml` | 全量编译 + 集群验证 | 中等（首次30-60分钟） | `docker/cluster/quick-start-source.sh` 一键 |
> 
> 工作流：`改源码 → docker exec builder make → 重启运行时容器 → 验证`  
> 两个方案都挂载本地源码目录，Builder 容器自动编译并产出到共享卷，GTM/CN/DN 节点直接使用编译产物启动。

### `scripts/` — 部署脚本 (⭐ 分层清晰)

| 层次 | 脚本 | 用途 |
|------|------|------|
| 用户面向 | `opentenbase.sh` | 一键部署入口 |
| 用户面向 | `setup-apt.sh` / `setup-rpm.sh` | 仓库配置 |
| 用户面向 | `switch-version.sh` / `uninstall.sh` | 版本切换 / 卸载 |
| 开发者 | `tools/build-deb.sh` | 本地 DEB 构建 |
| 开发者 | `tools/sign-packages.sh` | GPG 签名 |
| 开发者 | `tools/release.sh` | 发布流程 |

### `config/` — 配置模板 (⭐ 版本分层)

```
config/
├── gtm.conf.template           ← GTM 全局事务管理器
├── postgresql.conf.coord.template ← Coordinator 节点
├── postgresql.conf.dn.template ← Datanode 节点
├── opentenbase.conf            ← 主配置 (默认 = v5.0)
├── v5.0/opentenbase.conf       ← v5.0 专属 (含 forward_port)
├── v2.6.0/opentenbase.conf     ← v2.6.0 专属 (无 forward_port)
├── v2.5.0/opentenbase.conf     ← v2.5.0 专属
└── lowmem/postgresql.conf.lowmem ← 低内存专用 (2-4GB)
```

### `patches/` — 编译兼容补丁 (4 个)

| 补丁 | 用途 |
|------|------|
| `01-bool-stdbool.patch` | GCC 13+ bool/_Bool 类型兼容 |
| `02-nolic-sharding.patch` | 分片许可处理 |
| `03-atomic128-x86.patch` | x86 128-bit 原子操作用 `__atomic` 替代 `libatomic` |
| `04-gtm-thread-bind.patch` | GTM 线程绑定修复（≤2 核服务器启动失败，PR #69） |

### `test/` — 五层测试体系 (⭐ 全仓库最完善)

冒烟测试 → 多节点集成 → 版本切换 → Docker E2E → 高级专项（连接池/数据类型/故障转移/性能/分布式事务）

### `binaries/` — 辅助静态工具 (⚠️ 无安装包)

仅 2 个文件：`sshpass-x86_64` (746KB) + `sshpass-aarch64` (66KB)。
用于 openEuler/EulerOS/精简容器等无包管理器的环境。
**本文档第一行已加醒目免责声明：安装包在 GitHub Releases。**

### `systemd/` — 服务管理

`opentenbase-server.service` + `.tmpfiles`，无冗余。

---

## 完整的安装包清单

### 支持的 OpenTenBase 版本

| 版本 | 状态 | CI 自动构建 | Release 数 | 上游分支 |
|------|------|:----------:|-----------|---------|
| **v5.0** | ✅ 活跃 | ✅ | 5 个 (p10~p32) | v5.0 |
| **v2.6.0** | ✅ LTS | ✅ | 内嵌于 v5.0 release | v2.6.0 |
| **v2.5.0** | ✅ LTS | ✅ | 内嵌于 v5.0 release | v2.5.0 |

### DEB 包完整矩阵

每个格子 = 1 个 version × 1 个 distro × 1 个 arch 的组合。
**每个组合产出 6 个子包**：opentenbase, -server, -client, -contrib, lib-dev, -doc。

```
发行版 (codename)         v5.0 amd64   v5.0 arm64   v2.6.0 amd64  v2.6.0 arm64  v2.5.0 amd64  v2.5.0 arm64
────────────────────────────────────────────────────────────────────────────────────────────────────────────
Ubuntu 20.04 (focal)       ✅ 6包       ✅ 6包        ✅ 6包        ✅ 6包         ✅ 6包        ✅ 6包
Ubuntu 22.04 (jammy)       ✅ 6包       ✅ 6包        ✅ 6包        ✅ 6包         ✅ 6包        ✅ 6包
Ubuntu 24.04 (noble)       ✅ 6包       ✅ 6包        ✅ 6包        ✅ 6包         ✅ 6包        ✅ 6包
Ubuntu 25.04 (plucky)      ✅ 6包       ✅ 6包        ✅ 6包        ✅ 6包         ✅ 6包        ✅ 6包
Debian 11 (bullseye)       ✅ 6包       ✅ 6包        ✅ 6包        ✅ 6包         ✅ 6包        ✅ 6包
Debian 12 (bookworm)       ✅ 6包       ✅ 6包        ✅ 6包        ✅ 6包         ✅ 6包        ✅ 6包
Debian 13 (trixie)         ✅ 6包       ✅ 6包        ✅ 6包        ✅ 6包         ✅ 6包        ✅ 6包

DEB 小计                 7×6=42        7×6=42       7×6=42        7×6=42        7×6=42        7×6=42
────────────────────────────────────────────────────────────────────────────────────────────────────────────
DEB 总计: 42×6 = 252 个 .deb 包 (矩阵全覆盖 ✅，2026-07-02 扩展 arm64 至全发行版)
```

### RPM 包完整矩阵

每个格子 = 1 个 version × 1 个 distro × 1 个 arch 的组合。
**每个组合产出 ~6 个子包**。

```
发行版                      v5.0 x86_64  v5.0 aarch64  v2.6.0 x86_64 v2.6.0 aarch64 v2.5.0 x86_64 v2.5.0 aarch64
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
CentOS Stream 8             ✅ ~6包      ✅ ~6包         ✅ ~6包       ✅ ~6包        ✅ ~6包       ✅ ~6包
CentOS Stream 9             ✅ ~6包      ✅ ~6包         ✅ ~6包       ✅ ~6包        ✅ ~6包       ✅ ~6包
Rocky Linux 8               ✅ ~6包      ✅ ~6包         ✅ ~6包       ✅ ~6包        ✅ ~6包       ✅ ~6包
Rocky Linux 9               ✅ ~6包      ✅ ~6包         ✅ ~6包       ✅ ~6包        ✅ ~6包       ✅ ~6包
AlmaLinux 8                 ✅ ~6包      ✅ ~6包         ✅ ~6包       ✅ ~6包        ✅ ~6包       ✅ ~6包
AlmaLinux 9                 ✅ ~6包      ✅ ~6包         ✅ ~6包       ✅ ~6包        ✅ ~6包       ✅ ~6包
Fedora 40                   ✅ ~6包      ✅ ~6包         ✅ ~6包       ✅ ~6包        ✅ ~6包       ✅ ~6包
openEuler 22.03             ✅ ~6包      ✅ ~6包         ✅ ~6包       ✅ ~6包        ✅ ~6包       ✅ ~6包
openEuler 24.03             ✅ ~6包      ✅ ~6包         ✅ ~6包       ✅ ~6包        ✅ ~6包       ✅ ~6包

RPM 小计                  9×6=54       9×6=54        9×6=54        9×6=54        9×6=54        9×6=54
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
RPM 总计: 54+54+54+54+54+54 = 324 个 .rpm 包 ✅ 全覆盖
```

> **里程碑**: CentOS Stream 8/9 aarch64 通过 `quay.io/centos/centos:stream8/9` + `ubuntu-24.04-arm` runner 实现 CI 自动化。openEuler 24.03 通过 `quay.io/openeuler/openeuler:24.03-lts` 实现。

---

### 覆盖率统计

> 基于 CI 构建矩阵（提交 `5a19b9b` 已实现 RPM aarch64 100% 全覆盖）。矩阵覆盖 ≠ 已发布 Release 覆盖，但每次打 tag 会触发矩阵内全部 job 构建。

| 维度 | 总数 | 矩阵覆盖 | 缺失 | 覆盖率 |
|------|------|--------|------|--------|
| DEB amd64 | 126 包 | 126 | 0 | **100%** ✅ |
| DEB arm64 | 126 包 | 126 | 0 | **100%** ✅ |
| RPM x86_64 | 162 包 | 162 | 0 | **100%** ✅ |
| RPM aarch64 | 162 包 | 162 | 0 | **100%** ✅ |
| **总计** | **~576 包** | **~576** | **0** | **100%** ✅ |

### 覆盖率可视化

```
DEB amd64     ████████████████████████████████████████ 100%  ✅
DEB arm64     ████████████████████████████████████████ 100%  ✅
RPM x86_64    ████████████████████████████████████████ 100%  ✅
RPM aarch64   ████████████████████████████████████████ 100%  ✅  (2026-07-03 全覆盖)

✅ 所有发行版 × 所有版本 × 双架构全部覆盖 — 无缺失
```

```
矩阵扩展历史（2026-07-03 里程碑）:
  ✅ build-deb.yml arm64  — 21 job (7 distro × 3 ver)，100% 覆盖
  ✅ build-rpm.yml aarch64 — 27 job (9 distro × 3 ver)，100% 覆盖
  ✅ 新增 fedora-40 aarch64 (quay.io/fedora/fedora:40)
  ✅ 新增 rockylinux-8 / almalinux-8 aarch64
  ✅ 新增 centos-stream-8/9 aarch64 (quay.io/centos/centos:stream8/9 + ubuntu-24.04-arm runner)
  ✅ 新增 openEuler 24.03 x86_64/aarch64 (quay.io/openeuler/openeuler:24.03-lts)
```

### 不在 CI 中的特殊发行版（仅手动验证）

| 发行版 | 架构 | 验证方式 | CI 自动构建 |
|--------|------|---------|:----------:|
| EulerOS 2.0 | aarch64 | hdspace CLI 手动验证 ✅ | ❌ (需华为云 runner) |
| HCE 2.0 (华为云) | aarch64 | 端到端手动 ✅ | ❌ (需华为云 runner) |

> **说明**: openEuler 24.03 已纳入 CI 矩阵 (`5a19b9b`)，不再是"特殊发行版"。EulerOS/HCE 因需华为云专属 runner，作为手动验证项保留。

---

### 每个 Release 的实际包数

| Release | 日期 | 包数 | 内容 |
|---------|------|:---:|------|
| v5.0-p32 | 2026-06-29 | **203** | DEB 186 + RPM (meta only?) + install.sh + checksums |
| v5.0-p31 | 2026-06-28 | 33 | v5.0 核心包 |
| v5.0-p13 | 2026-06-02 | 155 | 早期完整构建 |
| v5.0-p12 | 2026-06-02 | 153 | 早期完整构建 |
| v5.0-p10 | 2026-06-02 | 162 | 早期完整构建 |
| **合计** | | **706** | |

---

## CI 构建流水线

### 主力流水线：`build-deb.yml` + `build-rpm.yml`

触发条件：`git tag v*` / `workflow_dispatch` / `workflow_call`

```
build-deb.yml (17KB)
├─ setup-matrix (动态生成 amd64 矩阵)
│     for ver in 5.0,2.6.0,2.5.0:
│       for distro in focal/jammy/noble/plucky/bullseye/bookworm/trixie:
│         生成 21 个并行 job
│
├─ build-deb-amd64 ← 使用上方动态矩阵
│     每个 job: 安装依赖 → 拉取上游源码 → 打补丁 → configure+make → debuild → 产出6个.deb
│
└─ build-deb-arm64 ← 动态矩阵 (21 个 job)
      每个 job: 同上流程，跑在 ubuntu-24.04-arm runner 上

build-rpm.yml (18KB)
├─ setup-matrix (动态生成 x86_64 矩阵)
│     for ver in 5.0,2.6.0,2.5.0:
│       for distro in centos-stream-8/9, rockylinux-8/9, almalinux-8/9, fedora-40, openeuler-22.03, openeuler-24.03:
│         生成 27 个并行 job
│
├─ build-rpm-x86_64 ← 使用上方动态矩阵
│     每个 job: 安装依赖 → 拉取上游源码 → rpmbuild → 产出~6个.rpm
│
└─ build-rpm-aarch64 ← 静态手写矩阵 (27 个 job)
      每个 job: docker run → 在 ARM 容器内 rpmbuild (ubuntu-24.04-arm runner)
      包含: centos-stream-8/9, rockylinux-8/9, almalinux-8/9, fedora-40, openeuler-22.03, openeuler-24.03

release.yml
├─ build-deb (workflow_call)
├─ build-rpm (workflow_call)
├─ test (冒烟测试)
└─ release:
      ├─ 下载所有 Artifacts
      ├─ GPG 签名
      ├─ 生成 checksums.sha256
      └─ 创建 GitHub Release → 触发 deploy-repo.yml → CDN 同步
```

### 辅助流水线：`build-multi.yml`

```
build-multi.yml (10KB) — 独立 DEB 构建，支持多版本
├─ setup job: 动态决定版本 (workflow_dispatch input / tag / default)
├─ 使用 docker/build/ 预构建容器 (7 个发行版)
├─ 支持 v5.0 / v2.6.0 / v2.5.0 三版本
├─ 7 个发行版 (focal/jammy/noble/plucky/bullseye/bookworm/trixie)
└─ 产出 .deb → Docker 冒烟测试 → 创建 Release (仅 git tag 时)
```

---

## 分发链路

```
GitHub Actions 完成构建
    │
    ├────► GitHub Releases
    │      每个 Release: 150-200+ 个 .deb/.rpm + install.sh + checksums.sha256
    │      用途: 直接下载, 历史追溯, GPG 验证
    │
    └────► deploy-repo.yml (自动触发)
            │
            ├────► GitHub Pages (APT/RPM 仓库)
            │      apt/ → pool/ + dists/ (deb 仓库元数据)
            │      rpm/ → el8/el9/fedora/ + repodata/ (yum 元数据)
            │      用途: apt update / dnf makecache 标准包管理访问
            │
            └────► Cloudflare CDN
                   repo.blackevil217.com
                   ├─ /scripts/  ← 一键部署脚本
                   ├─ /apt/      ← 回源 GitHub Pages
                   ├─ /rpm/      ← 回源 GitHub Pages
                   └─ /binaries/ ← sshpass 静态工具
                   
                   国内实测 (华为云 EulerOS aarch64, 华东):
                     GPG Key:      0.6s vs 132s (~200x)
                     Packages索引:  0.3s vs 45s  (~150x)
                     RPM 5.5MB:    1.2s vs 210s (~175x)
```

---

## 已知问题与缺口

### 🔴 覆盖率缺口

| 缺口 | 影响范围 | 原因 | 可修复 |
|------|---------|------|:---:|
| ~~DEB arm64 缺 ubuntu-20.04/25.04/debian-13~~ | ~~54 个 .deb~~ | 已在 `9f2cfec` 扩展矩阵修复 | ✅ 已修 |
| ~~DEB arm64 debian-11 仅 v5.0~~ | ~~12 个 .deb~~ | 已在 `9f2cfec` 扩展矩阵修复 | ✅ 已修 |
| ~~RPM aarch64 缺 centos-stream-8/9~~ | ~~36 个 .rpm~~ | 已在 `5a19b9b` 用 `quay.io/centos/centos:stream8/9` + `ubuntu-24.04-arm` runner 修复 | ✅ 已修 |
| ~~RPM aarch64 缺 rocky8/alma8~~ | ~~36 个 .rpm~~ | 已在 `132f6fb` 扩展矩阵修复 | ✅ 已修 |
| ~~RPM aarch64 缺 fedora-40~~ | ~~18 个 .rpm~~ | 已在 `132f6fb` 用 `quay.io/fedora/fedora:40` 修复 | ✅ 已修 |
| ~~openEuler 24.03~~ | ~~0 包~~ | 已在 `5a19b9b` 用 `quay.io/openeuler/openeuler:24.03-lts` 修复 | ✅ 已修 |
| EulerOS 2.0 / HCE 2.0 | 手动验证 | 需华为云专属 runner | ⚠️ 手动 |
| ~~Docker 运行时镜像仅 2 个发行版~~ | — | 已新增 14 个直装版运行时镜像 | ✅ 已修 |

> **里程碑**: 所有 CI 可覆盖的缺口均已修复，总覆盖率 100%。仅 EulerOS/HCE 需华为云专属 runner，作为手动验证项。

### 🟡 结构问题

| 问题 | 位置 | 状态 |
|------|------|:---:|
| `binaries/` 名称为"二进制"但只有 sshpass | 目录命名 | ✅ 已加免责声明 |
| `libssh2-1.11.1.tar.gz` 重复在 rpm/ 和 docker/ | 文件管理 | ✅ 已建 vendor/ 规划 |
| `.wrangler/` 运行时状态入库 | .gitignore | ✅ 已创建 .gitignore |
| `config/` 缺 v5.0 版本目录 | 目录结构 | ✅ 已创建 config/v5.0/ |
| `build-multi.yml` 命名暗示多版本但只做 v5.0 | workflow | ✅ 已改名 + 补全 distro |

### 🟢 无问题项

| 项目 | 说明 |
|------|------|
| amd64/x86_64 覆盖率 | 100%, 全覆盖 ✅ |
| arm64/aarch64 覆盖率 | DEB arm64 100%、RPM aarch64 100% ✅ |
| Debian 打包规范 | 严格合规 |
| 测试体系 | 五层全覆盖 |
| 文档体系 | 7 篇教程 + 中英双语 |
| Docker 生态 | 5 场景覆盖, 7 个构建镜像 + 14 个成品运行时镜像 |
| CHANGELOG | 严格 Keep a Changelog |

---

## 修复建议与路线图

### 已完成 ✅

- [x] `binaries/README.md` 加免责声明
- [x] 创建 `config/v5.0/opentenbase.conf`
- [x] 创建 `.gitignore` (排除 .wrangler/)
- [x] 创建 `vendor/README.md` (依赖统一规划)
- [x] libssh2 源码迁移到 `vendor/libssh2-1.11.1.tar.gz` — 解决网络下载超时问题
- [x] 创建 `docker/build/docker-ubuntu-25.04.Dockerfile`
- [x] 创建 `docker/build/docker-debian-13.Dockerfile`
- [x] `build-multi.yml` 矩阵从 5 发行版扩展到 7 (ubuntu-20.04/22.04/24.04/25.04 + debian-11/12/13)
- [x] Docker Compose 二次编译（源码编译）支持 — `docker/dev/docker-compose.dev.yml` + `docker/cluster/docker-compose.source.yml` + 一键脚本
- [x] **GTM 线程绑定修复** — PR #69/#70 已合并，解决 2 核服务器启动失败问题 (2026-07-02)
- [x] **DEB ARM64 矩阵全覆盖** (`9f2cfec`) — ubuntu-20.04/25.04/debian-13 + debian-11 v2.6/v2.5 补齐，21 个 job (7×3)，覆盖率 57%→100%
- [x] **RPM aarch64 矩阵扩展** (`132f6fb`) — 新增 rockylinux-8/almalinux-8/fedora-40，18 个 job (6×3)，覆盖率 38%→75%
- [x] **Docker 运行时镜像直装版** — 新增 4 个成品运行时镜像：
  - `docker/runtime/Dockerfile.ubuntu-24.04` — apt 直装版
  - `docker/runtime/Dockerfile.debian-12` — apt 直装版
  - `docker/runtime/Dockerfile.rockylinux-9` — dnf 直装版
  - `docker/runtime/Dockerfile.openeuler-22.03` — dnf 直装版（替代旧 rpm2cpio 解包版）
- [x] **v5.0-p33 Release 发布** — 172 packages (DEB v5.0/v2.6/v2.5 全版本 + 部分 RPM)，含 PR #69 GTM 修复
- [x] **移除 Dockerfile LD_PRELOAD workaround** — v5.0-p33 包含 PR #69 修复，无需 noaffinity.so stub
- [x] **build-multi.yml 多版本支持** (`68942c5`) — 添加 setup job 和动态 version 参数，支持 v5.0/v2.6.0/v2.5.0
- [x] **Docker 运行时镜像全覆盖** (`0d0b5bd`) — 13 个发行版直装版镜像：
  - DEB: ubuntu-20.04/22.04/24.04/25.04, debian-11/12/13 (7个)
  - RPM: rocky-8/9, alma-8/9, fedora-40, openeuler-22.03 (6个)
- [x] **GHCR 发布 + 冒烟测试** (`5862ef3`) — docker-publish-all.yml workflow，自动推送 13 镜像 + CI 冒烟测试
- [x] **Docker 多架构 manifest** (`0863442`) — manifest verification + amd64/arm64 统一标签
- [x] **centos-stream aarch64 CI** (`9fedf9a`) — 使用 quay.io/centos/centos:stream9 + ubuntu-24.04-arm runner
- [x] **centos-stream-8 + openEuler 24.03 全覆盖** (`5a19b9b`) — RPM aarch64 覆盖率达 100% (9/9 发行版)

### 短期 (可立即实施)

- [ ] *短期任务已全部完成。剩余发行版覆盖见中期/长期。*

> 短期目标达成：ARM64/aarch64 矩阵覆盖率从 ~42% 提升到 ~93%（DEB arm64 100%、RPM aarch64 75%），Docker 用户可用直装版运行时镜像从 2 个提升到 6 个（含旧解包版）。

### 中期 (需评估)

- [x] ~~RPM aarch64 fedora-40~~ — 已用 `quay.io/fedora/fedora:40` 在 `132f6fb` 实现
- [x] ~~libssh2 源码迁移到 vendor/~~ — 已完成，解决网络下载超时问题
- [x] ~~创建 RPM 构建容器 Dockerfile 放到 docker/build/~~ — 可选优化，build-rpm.yml 已使用 container 模式动态安装
- [x] `build-multi.yml` 支持多版本 (v2.6, v2.5) — `68942c5` 实现，添加 setup job 和动态 version 参数
- [x] **Docker 运行时镜像扩展覆盖** — `0d0b5bd` 实现，已覆盖 13 个发行版：
  - DEB: ubuntu-20.04/22.04/24.04/25.04, debian-11/12/13 (7个)
  - RPM: rocky-8/9, alma-8/9, fedora-40, openeuler-22.03 (6个)
- [x] 所有运行时镜像推送到 GHCR，加 CI 冒烟测试 — `5862ef3` 实现 docker-publish-all.yml

### 长期 (大规模工程)

- [x] ~~openEuler 24.03 CI 自动化~~ — `quay.io/openeuler/openeuler:24.03-lts` + `ubuntu-24.04-arm` runner 已实现 (2026-07-03)
- [ ] **EulerOS 2.0 / HCE 2.0 手动验证** — 华为云开发环境已配置 (hdspace CLI)，作为手动验证项保留，不纳入 GitHub CI 自动化矩阵
- [x] ~~centos-stream aarch64~~ — `quay.io/centos/centos:stream8/9` + `ubuntu-24.04-arm` runner 已实现 (2026-07-03)
- [x] ~~Docker 多架构 manifest~~ — docker-publish-all.yml 已配置 `platforms: linux/amd64,linux/arm64` + manifest verification (2026-07-03)

> **长期任务进度**: 3/4 完成，1/4 手动验证 (EulerOS/HCE)。总覆盖率已达 **100%**。

---

> **维护者**: [@muzimu217](https://github.com/muzimu217)  
> **仓库**: [CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages)  
> **文档更新**: 2026-07-03 | RPM aarch64 100% 全覆盖 + openEuler 24.03 CI + 多架构 manifest
