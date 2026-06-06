# OpenTenBase Packages

[![GitHub Stars](https://img.shields.io/github/stars/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages?style=flat-square&logo=github&cacheSeconds=1800)](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/stargazers)
[![GitHub Downloads](https://img.shields.io/github/downloads/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/total?style=flat-square&logo=github&cacheSeconds=1800)](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases)
[![GitHub Release](https://img.shields.io/github/v/release/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages?style=flat-square&logo=github&cacheSeconds=1800)](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/latest)
[![License](https://img.shields.io/github/license/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages?style=flat-square&cacheSeconds=1800)](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/blob/main/LICENSE)

English | [中文](README_zh.md)

> **Official cross-platform package repository for OpenTenBase** — Enterprise-grade multi-format, multi-distro packaging and distribution for the OpenTenBase distributed SQL database.
>
> **[Quick Start Guide (快速开始)](docs/QUICKSTART.md)** — 5 minutes to install and run.

---

## Overview

**OpenTenBase Packages** is the official packaging and distribution project for [OpenTenBase](https://github.com/OpenTenBase/OpenTenBase), a distributed SQL database based on PostgreSQL. We provide standardized binary packages for major Linux distributions, supporting both DEB (Debian/Ubuntu) and RPM (RHEL/CentOS/Fedora) packaging systems across x86_64 and ARM64 architectures.

**Goal**: Build a **long-term maintained, auto-built, multi-version coexisting** official package repository for OpenTenBase — like PostgreSQL's `apt.postgresql.org` and Docker's `download.docker.com`.

---

## Features

| Feature | Description |
|---------|-------------|
| **Multi-format** | DEB (`.deb`) + RPM (`.rpm`) dual format support |
| **Multi-distro** | 14 distros: Ubuntu/Debian (7), Rocky/Alma/CentOS/Fedora/openEuler (7) |
| **Multi-arch** | x86_64 (amd64) + ARM64 (aarch64) |
| **Multi-version coexistence** | Install v5.0 / v2.6 / v2.5 and dev versions side-by-side, switch with `opentenbase-ctl switch` |
| **APT/RPM repository** | Official repository hosted on GitHub Pages — `apt install opentenbase` / `dnf install opentenbase` |
| **One-line install** | `curl -sSL ... \| sudo bash` — auto-configures repository, detects OS, resolves dependencies |
| **CI/CD automation** | GitHub Actions for automated build, sign, and publish |
| **GPG signed packages** | All release packages are GPG-signed (RSA 4096-bit) for authenticity verification |
| **systemd integration** | Native systemd service units, managed via `systemctl` |
| **Cluster management** | Built-in `opentenbase-ctl` script for one-command init, start, stop |
| **Cloudflare CDN acceleration** | Global CDN acceleration mirror: `repo.blackevil217.com` |

---

## Quick Install

### APT Repository (Ubuntu / Debian) — Recommended

```bash
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash
sudo apt update
sudo apt install opentenbase
```

### YUM/DNF Repository (RHEL / CentOS / Fedora)

```bash
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh | sudo bash
sudo dnf install opentenbase
```

### Manual Install

```bash
# Download from releases: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases
# DEB: sudo apt install ./opentenbase_*.deb
# RPM: sudo dnf install ./opentenbase-*.rpm
```

### One-Click Deploy (Interactive)

```bash
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-cluster.sh | sudo bash
```

---

## Mirror Acceleration (China-Optimized)

The installation scripts automatically detect and use the fastest available mirror:

1. **Cloudflare CDN** (`repo.blackevil217.com/apt` for APT, `repo.blackevil217.com/rpm` for RPM) — global acceleration, free forever
2. **GitHub Pages** (`cduestc-openatom-open-source-club.github.io/OpenTenBase-Packages/`) — direct fallback

> **Note**: The `curl` commands in the Quick Install section download scripts from `raw.githubusercontent.com`. Once executed, the scripts will automatically configure your system to use the CDN-accelerated repository.

### China Speed Test (2026-06-02)

**Test Environment**: Huawei Cloud EulerOS 2.0 aarch64 (East China region)

| Test | Cloudflare CDN | GitHub Pages | Speedup |
|------|---------------|--------------|---------|
| Download GPG Key | **0.6s** | 2m12s | **~200x** |
| Download Packages index | **0.3s** | 45s | **~150x** |
| Download opentenbase-server RPM (5.5MB) | **1.2s** | 3m30s | **~175x** |

**Conclusion**: Cloudflare CDN works in China without VPN, with ~150-200x speedup. Scripts auto-detect: CDN first, fallback to GitHub Pages on timeout.

### China Installation Verification (EulerOS 2.0 aarch64)

| Test | Result | Notes |
|------|--------|-------|
| `setup-rpm.sh` execution | ✅ | Auto-selected CDN mirror |
| `dnf install opentenbase` | ✅ | Installed from CDN repo |
| Installed versions | ✅ | v5.0, v2.6.0, v2.5.0 co-existing |
| Version switching | ✅ | `opentenbase-switch-version` works |
| Cluster startup | ✅ | GTM + Coordinator + Datanode all normal |

---

## System Requirements

| Resource | Minimum | Recommended | Notes |
|----------|---------|-------------|-------|
| **RAM** | 3 GB | 4 GB+ | OpenTenBase pooler cache requires ~1GB+ **non-swappable** shared memory per node. A single-machine cluster (GTM + Coordinator + Datanode) needs at least 3GB. |
| **Disk** | 2 GB | 10 GB+ | Binary packages (~500MB) + data directory |
| **CPU** | 1 core | 2+ cores | GTM thread count auto-detected from CPU cores |
| **OS** | Ubuntu 20.04+, Debian 11+, RHEL 8+, Fedora 40+ | See platform matrix below | |

> **Important**: The `opentenbase-ctl init` script automatically detects available RAM and tunes `max_connections`, `max_pool_size`, and `shared_buffers` accordingly. On servers with <4GB RAM, reduced settings are applied automatically. On servers with <3GB RAM, a warning is displayed as the cluster may fail to start due to OOM (Out of Memory).

---

## Package Inventory

| Package | Format | Description |
|---------|--------|-------------|
| `opentenbase` | DEB / RPM | Metapackage — depends on server + client |
| `opentenbase-server` | DEB / RPM | Server binaries (postgres, gtm, pg_ctl) + service driver + cluster management |
| `opentenbase-client` | DEB / RPM | Client utilities (psql, pg_dump, pg_restore, etc.) |
| `opentenbase-contrib` | DEB / RPM | Extensions (pgbench, pg_stat_statements, postgres_fdw, etc.) |
| `libopentenbase-dev` | DEB / RPM | Development headers + static libraries + pg_config |
| `opentenbase-doc` | DEB / RPM | Documentation |

---

## Platform Support Matrix (CI Verified)

| Distribution | Version | DEB | RPM | x86_64 | aarch64 |
|-------------|---------|:---:|:---:|:------:|:------:|
| Ubuntu | 20.04 / 22.04 / 24.04 / 25.04 | ✅ | — | ✅ | ✅ |
| Debian | 11 / 12 / 13 | ✅ | — | ✅ | ✅ |
| Rocky Linux | 8 / 9 | — | ✅ | ✅ | ✅ (el9 only) |
| AlmaLinux | 8 / 9 | — | ✅ | ✅ | ✅ (el9 only) |
| CentOS Stream | 8 / 9 | — | ✅ | ✅ | — |
| Fedora | 40 | — | ✅ | ✅ | — |
| openEuler | 22.03 | — | ✅ | ✅ | — |

> **Total**: 15 distros, 150+ packages per release — 3 versions × 15 distros
>
> **aarch64 Note**: RPM aarch64 packages are currently only available for el9 (Rocky/Alma 9). The setup scripts automatically fall back to x86_64 when an aarch64 repo is unavailable. DEB aarch64 is fully supported for all distros.
>
> **ARM64 Verified**: openEuler 22.03 aarch64 (hdspace cloud, 4vCPU 8GiB) + Ubuntu 24.04 aarch64 — full cluster deployment, SQL connectivity, and distributed table operations confirmed.

---

## Quick Start

```bash
# 1. Initialize cluster (GTM + Coordinator + Datanode)
opentenbase-ctl init

# 2. Start cluster
opentenbase-ctl start

# 3. Check cluster status
opentenbase-ctl status

# 4. Connect to database
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1

# 5. Stop cluster
opentenbase-ctl stop
```

### Docker Compose Deployment

Deploy a complete OpenTenBase cluster (GTM + Coordinator + 2 Datanodes) with Docker Compose:

```bash
# Download the deployment script
curl -sLO https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/docker/test-docker.sh
bash test-docker.sh

# Start the cluster
cd /tmp/otb-docker/compose
docker compose up -d --build

# Connect to the database
docker compose exec coordinator psql -h 127.0.0.1 -U opentenbase -d postgres

# Stop the cluster
docker compose down -v
```

> **Note for users in China**: Docker Hub is not directly accessible from mainland China. You need to configure a Docker registry mirror. Edit `/etc/docker/daemon.json`:
>
> ```json
> {
>   "registry-mirrors": ["https://docker.m.daocloud.io"]
> }
> ```
>
> Then restart Docker: `sudo systemctl restart docker`

### Multi-Version Management

OpenTenBase supports multiple versions installed side-by-side, similar to PostgreSQL's `postgresql-14`, `postgresql-15` model. Each version has its own isolated directory tree.

```bash
# List installed versions
opentenbase-switch-version

# Switch to a specific version
opentenbase-switch-version 5.0

# Switch to another version
opentenbase-switch-version 2.6.0

# Verify current version
readlink /etc/opentenbase/current
```

**Versioned directory structure:**

| Path | Purpose |
|------|---------|
| `/usr/lib/opentenbase/<version>/` | Binaries and libraries per version |
| `/etc/opentenbase/<version>/` | Configuration per version |
| `/var/lib/opentenbase/<version>/` | Data directory per version |
| `/var/log/opentenbase/<version>/` | Logs per version |
| `/etc/opentenbase/current` | Symlink to active version |

**Supported versions:** `5.0` (stable), `2.6.0`, `2.5.0` (historical), `master-{sha}` (development), `latest` (alias)

---

## Architecture Overview

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
│                     │   GPG Signature   │                       │
│                     └─────────┬─────────┘                       │
│                               │                                 │
│                     ┌─────────▼─────────┐                       │
│                     │  Version Manager  │                       │
│                     │  v5.0 / v2.6 / …  │                       │
│                     └─────────┬─────────┘                       │
│                               │                                 │
│                     ┌─────────▼─────────┐                       │
│                     │  GitHub Actions   │                       │
│                     │  Auto Build & Ship│                       │
│                     └───────────────────┘                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Installation Paths

| Path | Purpose |
|------|---------|
| `/usr/lib/opentenbase/<version>/` | Binaries and libraries (isolated from system PostgreSQL) |
| `/etc/opentenbase/<version>/` | Configuration files |
| `/var/lib/opentenbase/<version>/` | Data directory |
| `/var/log/opentenbase/<version>/` | Log directory |
| `/usr/bin/opentenbase-ctl` | Cluster management script |

---

## Deployment Options

OpenTenBase supports two deployment approaches:

| Aspect | Pre-built Packages | Source Build |
|--------|-------------------|--------------|
| **Deploy time** | ~2 minutes | 30-60 minutes (first time) |
| **Customization** | Not supported | Full control (debug, cassert, etc.) |
| **Best for** | Production, quick testing | Development, learning, contributing |
| **Image size** | ~500 MB | ~2 GB |

**Recommendation**: Use pre-built packages for production and quick evaluation. Use source builds for development, debugging, and contributing to the project. See [source-build-guide.md](docs/source-build-guide.md) for detailed source build instructions.

---

## Build from Source

### Docker Build (Recommended)

```bash
git clone https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages.git
cd OpenTenBase-Packages

# Build for all distributions
./scripts/build-multi.sh --all

# Build for Ubuntu 24.04 only
./scripts/build-multi.sh -d ubuntu -v 24.04

# Build RPM only
./scripts/build-multi.sh --rpm
```

### Local Build

```bash
# Install build dependencies
sudo apt install -y debhelper-compat bison flex perl libreadline-dev \
    zlib1g-dev libssl-dev libxml2-dev libldap2-dev uuid-dev pkg-config

# Build DEB packages
./scripts/build-deb.sh

# Build RPM packages
./scripts/build-rpm.sh
```

---

## Directory Structure

```
OpenTenBase-Packages/
├── README.md                # English documentation
├── README_zh.md             # Chinese documentation
├── CHANGELOG.md             # Release history
├── TEST-PLAN.md             # Test matrix and results
├── config/                  # Configuration templates
├── debian/                  # DEB packaging rules
├── rpm/                     # RPM packaging rules
├── docker/                  # Docker build environments
├── scripts/                 # Build, release, setup scripts
├── patches/                 # Source patches
├── test/                    # Automated tests
│   └── advanced/            # Advanced test suites
└── docs/                    # Guides and references
    ├── QUICKSTART.md        # Quick start guide
    ├── CONTRIBUTING.md      # Contributing guide
    ├── source-build-guide.md # Build from source
    ├── 01-quickstart.md     # Tutorial: quick start
    ├── 02-basic-ops.md      # Tutorial: basic operations
    ├── 03-architecture.md   # Tutorial: architecture
    ├── 04-advanced.md       # Tutorial: advanced usage
    ├── 05-troubleshoot.md   # Tutorial: troubleshooting
    ├── 06-best-practices.md # Tutorial: best practices
    ├── 07-deployment.md     # Tutorial: deployment
    └── archive/             # Archived planning docs
```

---

## Release History

| Release | Date | Assets | Notes |
|---------|------|--------|-------|
| v5.0-p11 | 2026-06-02 | 156 | Cloudflare CDN acceleration documentation |
| v5.0-p10 | 2026-06-02 | 156 | ARM64 native builds + Docker E2E + version switch fix |
| v5.0-p9 | 2026-06-01 | 150 | Multi-version end-to-end verification on ARM64 |
| v5.0-p8 | 2026-06-01 | 150 | Stress test (7/7), cross-machine deployment, dh_install fix |
| v5.0-p4 | 2026-05-30 | 150 | Advanced test suite (31/31), all 14 distros |
| v5.0-p3 | 2026-05-29 | 150 | Multi-version (5.0+2.6.0+2.5.0), 15 distros |
| v5.0-p2 | 2026-05-28 | 50 | Fix lib/postgresql path, all 15 distros |
| v5.0 | 2026-05-18 | 7 | First release |

See [GitHub Releases](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases) for all releases.

---

## Roadmap

**Vision**: Build a long-term maintained, auto-built, multi-version coexisting official package repository for OpenTenBase, like PostgreSQL's `apt.postgresql.org` and Docker's `download.docker.com`.

### Phase 1: Foundation (1-2 weeks) -- Completed

- [x] Docker build environments for all target distros
- [x] CI workflows: 30 build targets (16 DEB + 14 RPM)
- [x] x86_64 + aarch64 dual architecture support
- [x] Multi-version coexistence (versioned paths + symlink switching)
- [x] Automated release pipeline (tag triggers build + test + publish)

### Phase 2: Official APT Repository (1-2 months) -- Completed

- [x] Multi-version management (`opentenbase-switch-version`)
- [x] One-click installation script
- [x] GPG signing integration (RSA 4096-bit, CI automated)
- [x] APT/RPM repository hosting (GitHub Pages, free)

### Phase 3: Cross-Platform Ecosystem (3-6 months)

- [x] RPM package support (RHEL/CentOS/Rocky/Fedora/openEuler)
- [x] Automated CI/CD pipeline
- [ ] Standardize packaging specifications
- [ ] Code quality review and upstream contribution

### Full Distribution Support Matrix

#### DEB Packages (16 build targets)

| Distribution | Version | Codename | x86_64 | aarch64 |
|-------------|---------|----------|--------|---------|
| Ubuntu | 18.04 | bionic | yes | - |
| Ubuntu | 18.10 | cosmic | yes | - |
| Ubuntu | 19.04 | disco | yes | - |
| Ubuntu | 19.10 | eoan | yes | - |
| Ubuntu | 20.04 | focal | yes | yes |
| Ubuntu | 22.04 | jammy | yes | yes |
| Ubuntu | 22.10 | kinetic | yes | - |
| Ubuntu | 23.10 | mantic | yes | - |
| Ubuntu | 24.04 | noble | yes | yes |
| Ubuntu | 24.10 | oracular | yes | - |
| Ubuntu | 25.04 | plucky | yes | yes |
| Debian | 9 | stretch | yes | - |
| Debian | 10 | buster | yes | - |
| Debian | 11 | bullseye | yes | yes |
| Debian | 12 | bookworm | yes | yes |
| Debian | 13 | trixie | yes | yes |

#### RPM Packages (14 build targets)

| Distribution | Version | x86_64 | aarch64 |
|-------------|---------|--------|---------|
| CentOS Stream | 8 | yes | - |
| CentOS Stream | 9 | yes | yes |
| Rocky Linux | 8 | yes | - |
| Rocky Linux | 9 | yes | yes |
| AlmaLinux | 8 | yes | - |
| AlmaLinux | 9 | yes | yes |
| Fedora | 40 | yes | yes |
| OpenEuler | 22.03 | yes | yes |

**Total**: 30 build targets, 15+ distributions, x86_64 + aarch64.

> **ARM64 Note**: x86_64 packages are built in CI (GitHub Actions). ARM64 (aarch64) packages are built natively on ARM64 hardware — CI-verified ARM64 targets: openEuler 22.03 (RPM), Ubuntu 24.04 (DEB, verified on developer-1). Other ARM64 targets are built but not yet CI-verified.

---

## Testing

All 15 distros pass CI verification (install + cluster + SQL + advanced tests).

### Test Suites (38 tests total)

| Suite | Tests | Content |
|-------|-------|---------|
| Basic SQL | 1 | CREATE TABLE, INSERT, SELECT |
| Transactions | 6 | COMMIT/ROLLBACK, isolation, SAVEPOINT |
| Connection Pool | 6 | Concurrent connections, pool reload |
| Data Types | 7 | int, text, jsonb, timestamp, array |
| Performance | 6 | Bulk INSERT, JOIN, index effectiveness |
| Failover | 7 | Cluster health, stress R/W, data consistency |
| Stress Test | 7 | 100-row INSERT, batch UPDATE/DELETE, aggregation |

### Cross-Machine Deployment

Verified on real hardware: devenv (ARM64, GTM+Coordinator) + 47.108 (x86_64, Datanode) connected via SSH reverse tunnel.

```bash
# Run cross-machine test
./test/cross-machine-test.sh

# Trigger stress test in CI
gh workflow run stress-test.yml
```

---

## Known Limitations

| Limitation | Description |
|-----------|-------------|
| Multiple clusters on same machine | Not supported due to port conflicts; each machine runs one cluster (GTM + Coordinator + Datanode) |

---

## Troubleshooting

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

# 检查文件是否存在
ls -la /usr/bin/opentenbase-ctl
```

---

## Contributing

Contributions are welcome — code, bug reports, and improvement suggestions!

1. Fork this repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit and push your changes
4. Create a Pull Request

See [Contributing Guide](docs/CONTRIBUTING.md) for details.

---

## License

Same as OpenTenBase — [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

---

## Links

| Resource | Link |
|----------|------|
| **This project** | https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages |
| **Upstream repo** | https://github.com/OpenTenBase/OpenTenBase |
| **OpenTenBase docs** | https://github.com/OpenTenBase/OpenTenBase/wiki |
| **Issue tracker** | [Issues](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/issues) |

---

## Stats

[![Star History Chart](https://api.star-history.com/svg?repos=CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages&type=Date)](https://star-history.com/#CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages&Date)

---

**Maintainer**: muzimu217
**Last Updated**: 2026-06-02 (v5.0-p11, CDN acceleration documentation)
