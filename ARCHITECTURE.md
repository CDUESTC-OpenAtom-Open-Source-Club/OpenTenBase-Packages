# OpenTenBase Packages — 仓库架构全解

> **一分钟看懂：本仓库是 OpenTenBase 的打包工程源码。成品 .deb/.rpm 不在 Git 里，在 GitHub Releases（v5.0-p32 = 203 个文件）+ Cloudflare CDN（repo.blackevil217.com）。**

---

## 全景图

```
                          ┌─────────────────────────────────────┐
                          │         上游源码 (外部)               │
                          │   github.com/OpenTenBase/OpenTenBase │
                          │   (PostgreSQL 分布式 fork)            │
                          └──────────────┬──────────────────────┘
                                         │ git clone --branch v5.0
                                         ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                      本仓库 (Git Repo) — 打包配方                           │
│                                                                          │
│  debian/          rpm/            patches/        config/                │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │ control  │    │ .spec    │    │ 01-bool  │    │ *.conf   │          │
│  │ rules    │    │build-rpm │    │ 02-nolic │    │ *.tmpl   │          │
│  │ *.install│    │   .sh    │    │ 03-atom  │    │ v2.5/2.6 │          │
│  │ postinst │    │ libssh2  │    │ series   │    │ lowmem/  │          │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘          │
│                                                                          │
│  scripts/         docker/          test/           docs/                │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │一键部署.sh│    │ build/   │    │ smoke    │    │ 01~07.md │          │
│  │setup-apt │    │ cluster/ │    │ multi-   │    │ CONTRIB  │          │
│  │setup-rpm │    │ compose/ │    │ node     │    │ EulerOS  │          │
│  │uninstall │    │ dev/     │    │ version  │    │ archive/ │          │
│  │tools/    │    │ runtime/ │    │ e2e      │    │ diagrams │          │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘          │
│                                                                          │
│  systemd/         binaries/        .github/workflows/                    │
│  ┌──────────┐    ┌──────────┐    ┌────────────────────────────┐        │
│  │.service  │    │ sshpass*2│    │ build-deb.yml(17KB)       │        │
│  │.tmpfiles │    │(静态工具) │    │ build-rpm.yml(18KB)       │        │
│  └──────────┘    └──────────┘    │ build-multi.yml(9KB)       │        │
│                                  │ release.yml(9KB)           │        │
│                                  │ test.yml / test-all.yml    │        │
│                                  │ deploy-repo.yml (CDN同步)  │        │
│                                  └────────────────────────────┘        │
└──────────────────────┬───────────────────────────────────────────────────┘
                       │  触发: git push / tag / workflow_dispatch
                       ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                    GitHub Actions — 自动化构建                              │
│                                                                          │
│  build-deb.yml                    build-rpm.yml                          │
│  ┌──────────────────────┐        ┌──────────────────────┐               │
│  │ amd64: 7 distro×3ver │        │ x86_64: 8 distro×3ver│               │
│  │ = 21 个并行 job       │        │ = 24 个并行 job       │               │
│  │                      │        │                      │               │
│  │ arm64: 10 个 job      │        │ aarch64: 9 个 job    │               │
│  │ (4 distro, 3 ver,     │        │ (3 distro, 3 ver)    │               │
│  │  部分版本不全)         │        │                      │               │
│  └──────────┬───────────┘        └──────────┬───────────┘               │
│             │                               │                            │
│             └───────────────┬───────────────┘                            │
│                             ▼                                            │
│                    ┌────────────────┐                                    │
│                    │  release.yml   │  聚合产物 + GPG签名 + 创建Release    │
│                    └───────┬────────┘                                    │
│                            │                                             │
│              ┌─────────────┼─────────────┐                               │
│              ▼             ▼             ▼                                │
│     GitHub Releases   GitHub Pages   Cloudflare CDN                      │
│     (直接下载)        (APT/RPM仓库)   (全球加速)                           │
│     v5.0-p32:         apt install     repo.blackevil217.com              │
│     203 个文件         dnf install     国内实测150-200x加速                │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 核心原则

### 仓库里有什么 vs 没有什么

| | 在 Git 仓库里 | 不在 Git 仓库里 |
|---|---|---|
| **打包配方** | ✅ debian/, rpm/, patches/ | |
| **配置/脚本** | ✅ config/, scripts/, systemd/ | |
| **测试/文档** | ✅ test/, docs/ | |
| **CI 定义** | ✅ .github/workflows/ | |
| **Docker 环境** | ✅ docker/ (Dockerfile + compose) | |
| **静态辅助工具** | ✅ binaries/sshpass-* | |
| **成品 .deb/.rpm** | | ✅ GitHub Releases (700+ 个) |
| **APT/RPM 仓库索引** | | ✅ GitHub Pages |
| **上游源码** | | ✅ github.com/OpenTenBase/OpenTenBase |

### 为什么仓库里不放 .deb/.rpm？

1. **Git 不适合大文件** — 一个 Release 200+ 个文件，每个几十~几百 MB
2. **标准化做法** — PostgreSQL、Docker、Kubernetes 都不在 Git 里存放二进制包
3. **有专用的分发渠道** — GitHub Releases (原生支持) + CDN (全球加速)

---

## 目录逐项解析

### `debian/` — DEB 打包（结构最规范）

```
debian/
├── control          ← 定义 6 个子包及其依赖关系
├── rules (13KB)     ← 构建规则（configure → make → install → 打包）
├── changelog        ← Debian 格式的变更日志
├── copyright        ← 版权声明
├── not-installed    ← 排除文件列表
│
│  子包定义（每个子包一套 .install + .links + 维护脚本）:
│
├── opentenbase.install              ← 元包（空，纯依赖聚合）
├── opentenbase-server.install       ← 核心: postgres, gtm, opentenbase_ctl
├── opentenbase-server.dirs          ←   + 创建 /etc /var /usr/lib 目录
├── opentenbase-server.links         ←   + 符号链接
├── opentenbase-server.postinst      ←   + 安装后钩子(创建用户、ldconfig)
├── opentenbase-server.postrm        ←   + 卸载后清理
├── opentenbase-server.prerm         ←   + 卸载前停止服务
├── opentenbase-client.install       ← 客户端: psql, pg_dump, libpq
├── opentenbase-client.links
├── opentenbase-client.postinst
├── opentenbase-client.prerm
├── opentenbase-contrib.install      ← 扩展: pg_stat_statements, postgres_fdw
├── opentenbase-contrib.links
├── libopentenbase-dev.install       ← 开发: 头文件, pg_config, 静态库
├── opentenbase-doc.install          ← 文档: HTML手册, man pages
├── opentenbase-doc.docs
│
├── *.lintian-overrides              ← Lintian 检查白名单
└── source/format                    ← quilt (3.0)
```

**6 个子包依赖关系**：
```
opentenbase (元包)
    ├── opentenbase-server     (~500MB 核心服务)
    ├── opentenbase-client     (客户端工具 + libpq)
    ├── opentenbase-contrib    (推荐: 扩展组件)
    ├── opentenbase-doc        (建议: 文档)
    └── libopentenbase-dev     (建议: 开发库)
```

**评分: ⭐⭐⭐⭐⭐** — Debian Policy 合规，是全仓库最规范的部分。

---

### `rpm/` — RPM 打包（单 SPEC + 条件宏）

```
rpm/
├── opentenbase.spec              ← 单一 SPEC 文件，通过条件宏覆盖多发行版差异
│                                    %if 0%{?rhel} == 8 → gcc-toolset-11
│                                    %if 0%{?fedora}    → 最新工具链
│                                    %if 0%{?suse_version} → SUSE 适配
├── build-rpm.sh (112行)          ← 构建脚本: 打包源码 → rpmbuild
├── libssh2-1.11.1.tar.gz         ← 内置 libssh2 源码(Rocky 9 无此包)
└── README.md
```

**RPM 子包**（与 DEB 一致拆分为 server/client/contrib/libdev/doc + 元包）

**评分: ⭐⭐⭐⭐** — SPEC 写得专业，条件宏覆盖合理。但缺少 RHEL 7 支持（如果声称全系统的话）。

---

### `docker/` — 容器化（5 个子场景，结构合理）

**二次审核结论：Docker 目录结构是正确的，每个子目录有不同用途。**

```
docker/
│
├── Dockerfile                    ← 根级: 通用安装镜像 (Rocky 9 + dnf install opentenbase)
├── docker-compose.yml            ← 根级: 快速编排 (不依赖 build 子目录)
├── README.md                     ← Docker 使用说明
├── test-docker.sh                ← Docker E2E 测试入口
├── libssh2-1.11.1.tar.gz         ← (与 rpm/ 重复，建议统一)
│
├── build/                        ← 【场景1: 构建容器】(供 build-multi.yml 使用)
│   ├── docker-ubuntu-20.04.Dockerfile    ubuntu:20.04 + 构建依赖
│   ├── docker-ubuntu-22.04.Dockerfile    ubuntu:22.04 + 构建依赖
│   ├── docker-ubuntu-24.04.Dockerfile    ubuntu:24.04 + 构建依赖
│   ├── docker-debian-11.Dockerfile       debian:11 + 构建依赖
│   └── docker-debian-12.Dockerfile       debian:12 + 构建依赖
│   ⚠️ 仅 5 个 DEB 构建镜像，无 RPM 构建镜像
│   ⚠️ 缺 ubuntu-25.04, debian-13
│
├── cluster/                      ← 【场景2: 分布式集群部署】
│   ├── Dockerfile.centos         ←   CentOS Stream 9 + OpenTenBase 二进制
│   ├── Dockerfile.source         ←   源码编译镜像 (CentOS 9)
│   ├── config.ini                ←   集群拓扑配置
│   ├── postgres.conf             ←   PostgreSQL 配置
│   ├── setup.sh                  ←   集群初始化
│   ├── quick-start-source.sh     ←   快速启动
│   ├── docker-compose.source.yml ←   源码版编排
│   └── scripts/                  ←   辅助脚本
│
├── compose/                      ← 【场景3: 多节点 Compose 编排(生产级)】
│   ├── docker-compose.yml        ←   GTM:6666 + Coordinator:5432 + DN×2:15432/15433
│   └── README.md
│
├── dev/                          ← 【场景4: 开发环境】
│   ├── Dockerfile.builddev       ←   ubuntu:24.04 + gcc-12 + 全量构建依赖
│   ├── Dockerfile.runtime-dev    ←   运行时开发镜像
│   ├── docker-compose.dev.yml    ←   开发编排
│   └── scripts/                  ←   开发辅助
│
└── runtime/                      ← 【场景5: 运行时镜像】
    ├── Dockerfile.runtime        ←   openEuler 22.03 + 预装 OpenTenBase
    └── entrypoint.sh             ←   GTM/Coordinator/Datanode 启动入口
```

**评分: ⭐⭐⭐⭐** — Docker 生态 5 个场景覆盖完整，不是之前说的"内容稀疏"。

---

### `scripts/` — 脚本系统

```
scripts/
│
│  【用户面向脚本 — 通过 CDN 分发】
├── opentenbase.sh                ← 🎯 一键部署（主入口）
├── setup-apt.sh                  ← 配置 APT 仓库
├── setup-rpm.sh                  ← 配置 RPM 仓库
├── switch-version.sh             ← 版本切换 (v5.0 ↔ v2.6 ↔ v2.5)
├── uninstall.sh                  ← 卸载
├── build-from-source.sh          ← 源码编译
├── opentenbase-packages-key.asc  ← GPG 公钥
│
│  【开发者工具 — CI 内部使用】
├── tools/
│   ├── build-deb.sh (304行)      ← DEB 本地构建
│   ├── build-repo.sh             ← APT/RPM 仓库索引
│   ├── setup-apt-repo.sh         ← APT 仓库初始化
│   ├── sign-packages.sh          ← GPG 签名
│   ├── test-build.sh             ← 构建测试
│   ├── generate-release-notes.sh ← Release Notes
│   └── release.sh                ← 发布流水线
│
│  【扩展脚本】
└── extras/
    └── deploy-lowmem-datanode.sh ← 低内存节点特殊处理
```

**评分: ⭐⭐⭐⭐** — 用户面向 vs 开发工具分层清晰。

---

### `config/` — 配置模板

```
config/
├── gtm.conf.template               ← GTM 全局事务管理器
├── postgresql.conf.coord.template  ← Coordinator 节点
├── postgresql.conf.dn.template     ← Datanode 节点
├── opentenbase.conf                ← 主配置 (默认 v5.0)
├── pg_hba.conf.template            ← 客户端认证
├── opentenbase-psql                ← psql 包装脚本
├── opentenbase_config.ini.example  ← opentenbase_ctl 集群配置模板
├── v2.5.0/opentenbase.conf         ← 版本差异化配置
├── v2.6.0/opentenbase.conf
└── lowmem/postgresql.conf.lowmem   ← 低内存(2-4GB)专用配置
```

**⚠️ 缺失: v5.0 专属配置目录**（有 v2.5.0 和 v2.6.0 但没有 v5.0/）

**评分: ⭐⭐⭐⭐**

---

### `patches/` — 兼容补丁

```
patches/
├── series                       ← quilt 补丁栈管理
├── 01-bool-stdbool.patch        ← GCC 13+ bool/_Bool 类型兼容
├── 02-nolic-sharding.patch      ← 分片许可处理
└── 03-atomic128-x86.patch       ← x86 128-bit 原子操作 (用 __atomic 替代 libatomic)
```

3 个补丁覆盖跨发行版编译的核心兼容问题，针对性强。

**评分: ⭐⭐⭐⭐**

---

### `test/` — 测试体系

```
test/
├── smoke-test.sh                 ← 冒烟: 安装 + 二进制存在性 + ldconfig
├── multi-node-test.sh            ← 多节点: GTM + CN + DN 全链路
├── version-switch-test.sh        ← 版本切换: v5.0→v2.6→v2.5→v5.0
├── cross-machine-test.sh         ← 跨机器部署
├── docker-e2e-test.sh            ← Docker 端到端
├── docker-e2e-results.md         ← E2E 结果报告
├── run-advanced-tests.sh         ← 高级测试入口
└── advanced/                     ← 专项测试
    ├── test_connection_pool.sh   ←   连接池
    ├── test_data_types.sh        ←   数据类型
    ├── test_failover.sh          ←   故障转移
    ├── test_performance.sh       ←   基准性能
    └── test_transactions.sh      ←   分布式事务
```

**评分: ⭐⭐⭐⭐⭐** — 从冒烟到性能全覆盖。

---

### `docs/` — 文档体系

```
docs/
├── 01-quickstart.md               ← 快速入门
├── 02-basic-ops.md                ← 基本操作
├── 03-architecture.md             ← OpenTenBase 架构
├── 04-advanced.md                 ← 高级特性
├── 05-troubleshoot.md             ← 故障排查
├── 06-best-practices.md           ← 最佳实践
├── 07-deployment.md               ← 生产部署
├── QUICKSTART.md                  ← 速查卡片
├── CONTRIBUTING.md / _zh.md       ← 贡献指南(中英双语)
├── EulerOS-Deployment-Issues.md   ← 欧拉系统专项
├── archive/                       ← 历史文档
│   ├── GPG-SIGNING.md
│   ├── HANDOVER.md
│   ├── IMPROVEMENT-PLAN.md
│   ├── MULTI-VERSION-PLAN.md
│   └── VERIFICATION.md
└── diagrams/                      ← 架构图片
    ├── architecture.png
    ├── query-flow.png
    └── generate_diagrams.py
```

**评分: ⭐⭐⭐⭐⭐** — 7 篇渐进文档 + 中英双语，加分项。

---

### `binaries/` — 静态辅助工具

```
binaries/
├── sshpass-x86_64 (746KB)        ← 静态编译的 sshpass (x86_64)
├── sshpass-aarch64 (66KB)        ← 静态编译的 sshpass (ARM64)
└── README.md                     ← 构建说明 + CDN 地址
```

**用途**：opentenbase_ctl / pgxc_ctl 内部通过 SSH 管理远程节点，
某些环境（EulerOS、精简容器）没有 sshpass 包，需要静态二进制兜底。

**⚠️ 注意**：此目录名为 "binaries" 但只存放辅助工具，OpenTenBase 的安装包在 GitHub Releases。

**评分: ⭐⭐⭐** — 功能正确但命名有歧义。

---

### `systemd/` — 服务管理

```
systemd/
├── opentenbase-server.service    ← systemd service 单元
└── opentenbase-server.tmpfiles   ← 临时文件/运行时目录规则
```

**评分: ⭐⭐⭐⭐⭐** — 简练到位，无冗余。

---

### `.github/workflows/` — CI/CD（共 10 个 workflow）

| # | Workflow | 触发条件 | 职责 |
|---|----------|---------|------|
| 1 | `build-deb.yml` (17KB) | git tag / 手动 / workflow_call | **主力 DEB 构建**: amd64 21 job + arm64 10 job |
| 2 | `build-rpm.yml` (18KB) | git tag / 手动 / workflow_call | **主力 RPM 构建**: x86_64 24 job + aarch64 9 job |
| 3 | `build-multi.yml` (9KB) | git tag / 手动 | **辅助 DEB 构建**: 仅 v5.0，5 个发行版，用 docker/build/ 容器 |
| 4 | `build-sshpass.yml` (3KB) | 手动 / 文件变更 | 编译 sshpass 静态二进制 |
| 5 | `test.yml` (3KB) | 构建成功后 | 基础冒烟测试 |
| 6 | `test-all.yml` (12KB) | 手动 / Release 前 | 全发行版 + 多节点 + 版本切换 |
| 7 | `stress-test.yml` (13KB) | 手动 / 定时 | 连接池 + 事务 + 数据类型压力 |
| 8 | `release.yml` (9KB) | git tag / 手动 | **聚合产物 → 签名 → 创建 GitHub Release** |
| 9 | `deploy-repo.yml` (4KB) | Release 发布后 | 部署 APT/RPM 仓库到 GitHub Pages + 触发 CDN |
| 10 | `docker-publish.yml` (5KB) | Release / 手动 | 推送 Docker 镜像到 GHCR |

---

## CI 覆盖率矩阵（精确数据，源自代码逐行审核）

### build-deb.yml — DEB 构建

**amd64 动态矩阵** (build-deb.yml 第 35-52 行，循环生成)：

```
for ver in 5.0 2.6.0 2.5.0:
    ubuntu-20.04 (focal)     ✅
    ubuntu-22.04 (jammy)     ✅
    ubuntu-24.04 (noble)     ✅
    ubuntu-25.04 (plucky)    ✅
    debian-11 (bullseye)     ✅
    debian-12 (bookworm)     ✅
    debian-13 (trixie)       ✅

= 7 distros × 3 versions = 21 个 amd64 job
```

**arm64 静态矩阵** (build-deb.yml 第 246-290 行，手写 include)：

```
v5.0:   ubuntu-22.04, ubuntu-24.04, debian-11, debian-12  = 4
v2.6.0: ubuntu-22.04, ubuntu-24.04, debian-12             = 3
v2.5.0: ubuntu-22.04, ubuntu-24.04, debian-12             = 3
                                                          ─────
                                                          = 10 个 arm64 job

❌ arm64 缺失: ubuntu-20.04 (×3), ubuntu-25.04 (×3), debian-13 (×3),
               debian-11 v2.6.0 (×1), debian-11 v2.5.0 (×1) = 11 个缺失
```

### build-rpm.yml — RPM 构建

**x86_64 动态矩阵** (build-rpm.yml 第 34-54 行)：

```
for ver in 5.0 2.6.0 2.5.0:
    centos-stream-8        ✅
    centos-stream-9        ✅
    rockylinux-8           ✅
    rockylinux-9           ✅
    almalinux-8            ✅
    almalinux-9            ✅
    fedora-40              ✅
    openeuler-22.03        ✅

= 8 distros × 3 versions = 24 个 x86_64 job
```

**aarch64 静态矩阵** (build-rpm.yml 第 252-283 行)：

```
v5.0:   openeuler-22.03, rockylinux-9, almalinux-9  = 3
v2.6.0: openeuler-22.03, rockylinux-9, almalinux-9  = 3
v2.5.0: openeuler-22.03, rockylinux-9, almalinux-9  = 3
                                                      ───
                                                      = 9 个 aarch64 job

❌ aarch64 缺失: centos-stream-8/9 (×6), rockylinux-8 (×3),
                almalinux-8 (×3), fedora-40 (×3) = 15 个缺失
```

### 覆盖率总结

| | DEB | RPM | 合计 |
|---|---|---|---|
| amd64 / x86_64 | 21/21 ✅ 100% | 24/24 ✅ 100% | **45/45 ✅** |
| arm64 / aarch64 | 10/21 ⚠️ 48% | 9/24 ⚠️ 38% | **19/45 ⚠️ 42%** |
| **总体** | **31/42** | **33/48** | **64/90** |

> **结论**：amd64/x86_64 全覆盖，arm64/aarch64 覆盖面约 42%。部分缺失可能是 Docker Hub 上没有对应 ARM64 镜像（如 centos:stream8 arm64、fedora:40 arm64）。

---

## 分发链路

```
构建产物 (GitHub Artifacts)
    │
    ▼
┌─────────────────────────────────────────────────┐
│ 第 1 层: GitHub Releases (开发者/高级用户)        │
│                                                 │
│ 每个 Release 聚合该版本所有 Artifacts:            │
│   v5.0-p32 → 203 文件                           │
│   v5.0-p31 →  33 文件                           │
│   v5.0-p13 → 155 文件                           │
│   v5.0-p12 → 153 文件                           │
│   v5.0-p10 → 162 文件                           │
│                                                 │
│ 包含: .deb, .rpm, install.sh, checksums.sha256  │
│       GPG detached signature (.sig)             │
│       Source code (zip/tar.gz)                  │
│                                                 │
│ 用途: 手动下载, 历史版本追溯, GPG 验证            │
└────────────────────┬────────────────────────────┘
                     │
          deploy-repo.yml (自动触发)
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│ 第 2 层: APT/RPM 包仓库 (GitHub Pages)           │
│                                                 │
│ cduestc-openatom-open-source-club.github.io/    │
│   OpenTenBase-Packages/                         │
│                                                 │
│ ├── apt/                                        │
│ │   ├── pool/main/o/opentenbase/  ← .deb 包池    │
│ │   └── dists/                    ← Release/Packages 索引│
│ │                                                 │
│ └── rpm/                                        │
│     ├── el/8/x86_64/              ← RPM 包池     │
│     ├── el/9/x86_64/                             │
│     ├── fedora/40/x86_64/                        │
│     └── repodata/                 ← YUM 元数据   │
│                                                 │
│ 用途: apt update / dnf makecache 标准包管理访问   │
└────────────────────┬────────────────────────────┘
                     │
         Cloudflare CDN 回源代理
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│ 第 3 层: Cloudflare CDN (普通用户入口)            │
│                                                 │
│ repo.blackevil217.com                           │
│                                                 │
│ ├── /scripts/opentenbase.sh     ← 一键部署       │
│ ├── /scripts/setup-apt.sh       ← APT 仓库配置   │
│ ├── /scripts/setup-rpm.sh       ← RPM 仓库配置   │
│ ├── /scripts/uninstall.sh       ← 卸载           │
│ ├── /apt/        → 回源 GitHub Pages            │
│ ├── /rpm/        → 回源 GitHub Pages            │
│ └── /binaries/    → sshpass 静态二进制           │
│                                                 │
│ 实测加速 (华为云 EulerOS aarch64, 华东):          │
│   GPG Key:      0.6s vs 132s  (200x)            │
│   Packages索引:  0.3s vs 45s   (150x)            │
│   RPM 5.5MB:    1.2s vs 210s  (175x)            │
└─────────────────────────────────────────────────┘
```

## 用户安装路径

```
┌─ 路径A: 一键脚本（推荐）
│  curl ...opentenbase.sh | sudo bash
│      ├── 自动检测 OS (发行版 + 版本 + 架构)
│      ├── 选最优镜像 (CDN → GitHub Pages)
│      ├── setup-apt/setup-rpm → 配置包仓库
│      ├── apt/dnf install opentenbase
│      ├── 创建 opentenbase 用户 + SSH 免密
│      ├── 生成 INI 配置文件
│      └── opentenbase_ctl install → start → status
│
└─ 路径B: 手动包仓库
   ├── DEB: setup-apt.sh → apt install opentenbase
   └── RPM: setup-rpm.sh → dnf install opentenbase
```

---

## 关键问题清单

| # | 问题 | 严重度 | 位置 |
|---|------|--------|------|
| 1 | `binaries/` 命名歧义 — 只有 sshpass，没有安装包 | 🟡 中 | 目录名 |
| 2 | ARM64 CI 覆盖不到一半 (19/45) | 🟡 中 | build-deb/rpm.yml |
| 3 | `build-multi.yml` 命名 misleading — 只做 v5.0 DEB | 🟢 低 | workflow 命名 |
| 4 | `libssh2-1.11.1.tar.gz` 重复在 rpm/ 和 docker/ | 🟢 低 | 文件管理 |
| 5 | `config/` 缺 v5.0 目录 (有 v2.5.0 和 v2.6.0) | 🟢 低 | 目录结构 |
| 6 | `.wrangler/` Cloudflare 运行时状态误入库 | 🟢 低 | .gitignore |
| 7 | docker/build/ 缺 ubuntu-25.04, debian-13 Dockerfile | 🟢 低 | Dockerfile |

---

## 做得好的地方

- ✅ **DEB 打包**严格遵循 Debian Policy — 全仓库标杆
- ✅ **文档体系** 7 篇渐进教程 + 中英双语 + 架构图
- ✅ **测试矩阵** 冒烟→多节点→版本切换→E2E→压力 五层
- ✅ **CHANGELOG** 严格 Keep a Changelog 格式
- ✅ **10 个 GitHub Actions** 覆盖构建/测试/签名/发布/CDN 全链路
- ✅ **Docker 5 场景** — build/cluster/compose/dev/runtime 分工明确
- ✅ **amd64/x86_64 CI 100% 全覆盖** — 45 个独立 job
- ✅ **Cloudflare CDN 中国实测 150-200x 加速**
- ✅ **多版本并存** — side-by-side 安装 + switch-version 切换

---

## 修复建议优先级

1. **[高] 补充 `config/v5.0/` 目录** — 与 v2.5.0/v2.6.0 对齐
2. **[中] `binaries/` → `tools/` 或添加顶部注释说明** — 避免误导
3. **[中] 补齐 ARM64 CI** — 能加的发行版优先加（ubuntu-20.04 arm64, debian-13 arm64 等）
4. **[低] `build-multi.yml` 改名或扩展** — 变成真正的 multi-version + RPM
5. **[低] 统一 libssh2 源码** — 移到 vendor/ 目录
6. **[低] `.wrangler/` 加入 .gitignore** — 清理仓库

---

> **维护者**: [@muzimu217](https://github.com/muzimu217)  
> **仓库**: [CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages)  
> **本文档生成时间**: 2026-07-01 | 基于代码行级审计（二次审核）
