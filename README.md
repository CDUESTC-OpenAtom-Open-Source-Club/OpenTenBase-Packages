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
| **Multi-version coexistence** | Install v5.0 / v2.6 / v2.5 and dev versions side-by-side, switch with `opentenbase-switch-version` |
| **APT/RPM repository** | Official repository hosted on GitHub Pages — `apt install opentenbase` / `dnf install opentenbase` |
| **One-line install** | `curl -sSL ... \| sudo bash` — auto-configures repository, detects OS, resolves dependencies |
| **CI/CD automation** | GitHub Actions for automated build, sign, and publish |
| **GPG signed packages** | All release packages are GPG-signed (RSA 4096-bit) for authenticity verification |
| **systemd integration** | Native systemd service units, managed via `systemctl` |
| **Official cluster management** | Built-in `opentenbase_ctl` C++ binary — install/start/stop/status/expand/shrink via INI config |
| **Cloudflare CDN acceleration** | Global CDN acceleration mirror: `repo.blackevil217.com` |

---

## Quick Install

### One-Click Deploy (Recommended)

**Blank machine → running cluster in one command.** Supports both interactive and non-interactive modes:

```bash
# Interactive (asks a few questions, recommended for first-time users)
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/deploy-opentenbase.sh | sudo bash

# Non-interactive (all defaults, single-node, for CI/automation)
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/deploy-opentenbase.sh | sudo bash -s -- --yes
```

The script handles everything: install packages → create user → configure sshpass → path symlink → generate INI → `opentenbase_ctl install -c <config.ini>` → start, status check, and SQL verification.

### Package Repository (Manual)

#### APT (Ubuntu / Debian)

```bash
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash
sudo apt update && sudo apt install -y opentenbase
```

#### YUM/DNF (RHEL / CentOS / Fedora)

```bash
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh | sudo bash
sudo dnf install -y opentenbase
```

After package installation, deploy the cluster:

```bash
opentenbase_ctl install -c /tmp/otb_config.ini
opentenbase_ctl start
opentenbase_ctl status
```

> **Version control path note**:
> - `5.0` uses the `opentenbase_ctl` workflow with an INI file.
> - `2.5` / `2.6` use the `pgxc_ctl` workflow with `pgxc_ctl.conf` as the formal control path.

### Manual Download

```bash
# Download from releases: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases
# DEB: sudo apt install ./opentenbase_*.deb
# RPM: sudo dnf install ./opentenbase-*.rpm
```

### Uninstall

```bash
# Interactive uninstall (prompts before removing data)
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/uninstall.sh | sudo bash

# Full uninstall including data and logs (no prompts)
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/uninstall.sh | sudo bash -s -- --purge --yes
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
| **RAM** | 4 GB | 4 GB+ | OpenTenBase Coordinator requires ~4GB shared memory (SPM cache + connection pool + workfile manager). This is a hard requirement — cannot be reduced by tuning. |
| **Disk** | 2 GB | 10 GB+ | Binary packages (~500MB) + data directory |
| **CPU** | 1 core | 2+ cores | GTM thread count auto-detected from CPU cores |
| **OS** | Ubuntu 20.04+, Debian 11+, RHEL 8+, Fedora 40+ | See platform matrix below | |

> **Important**:
> - **2GB servers cannot run OpenTenBase** — Coordinator's shared memory (~4GB) exceeds available resources. This includes 2GB Cloud Studio containers.
> - **Containers (Docker/K8s)** have a hard cgroup memory limit and cannot add swap. Use 4GB+ containers only.
> - The setup script automatically detects memory and container environment, and will abort with clear guidance if requirements are not met.
> - On real VMs with 3-4GB RAM, the script can add swap to supplement available memory.

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
# 1. Install cluster (GTM + Coordinator + Datanode) — -c specifies topology
opentenbase_ctl install -c /tmp/otb_config.ini

# 2. Start cluster (cluster state is persisted after install, no -c needed)
opentenbase_ctl start

# 3. Check cluster status
opentenbase_ctl status

# 4. Connect to database
opentenbase-psql -h 127.0.0.1 -p 11003 -U opentenbase -d postgres

# 5. Stop cluster
opentenbase_ctl stop
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
| `/etc/opentenbase/<version>/` | Configuration files (includes `opentenbase_config.ini.example`) |
| `/var/lib/opentenbase/<version>/` | Data directory |
| `/var/log/opentenbase/<version>/` | Log directory |
| `/usr/bin/opentenbase-ctl` | Cluster management binary (symlink → official `opentenbase_ctl`) |

---

## Deployment Options

| Aspect | Pre-built Packages |
|--------|-------------------|
| **Deploy time** | ~2 minutes |
| **Image size** | ~500 MB |
| **Best for** | Production, quick testing, evaluation |

> For developers who want to build from source, see [source-build-guide.md](docs/source-build-guide.md).

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
| v5.0-p32 | 2026-06-29 | 156 | GTM ≤2-core crash fix (global `noaffinity.so` injection) + CN port 11003 + one-click deploy script e2e verification + DEB build fixes |
| v5.0-p31 | 2026-06-28 | 156 | Official `opentenbase_ctl` C++ binary, CLI11/libpqxx bundling |
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

**Cause**: The APT source was not updated, or the unsigned repository was skipped by `apt update`.

**Solution**:

```bash
# 1. Re-run the setup script (auto-detects signing status)
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash

# 2. Manually update
sudo apt update
sudo apt install opentenbase
```

### `The repository '... noble Release' is not signed`

**Cause**: The repository is missing GPG signature files (`Release.gpg` / `InRelease`). The setup script will automatically fall back to `trusted=yes` mode. If the error persists, re-run the setup script.

### `GPG key download failed`

**Cause**: Your network cannot reach the Cloudflare CDN or GitHub Pages.

**Solution**:

```bash
# Option 1: Retry (may be a transient network issue)
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash

# Option 2: Manually download and install the key
curl -sSL https://repo.blackevil217.com/apt/gpg-key.asc -o /tmp/key.asc
sudo gpg --batch --dearmor -o /usr/share/keyrings/opentenbase-archive-keyring.gpg < /tmp/key.asc

# Option 3: Use a proxy
export https_proxy=http://your-proxy:port
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash
```

### Third-party repository 404 errors during `apt-get update`

**Cause**: A third-party repository on your system is no longer available (e.g. `dl.modular.com`). This is unrelated to OpenTenBase.

**Solution**: Check files under `/etc/apt/sources.list.d/` and remove or disable the broken sources.

### `opentenbase-ctl: command not found` after installation

**Cause**: The installation did not complete, or `/usr/bin` is not in your PATH.

**Solution**:

```bash
# Check if installation succeeded
dpkg -l | grep opentenbase

# Reinstall
sudo apt install --reinstall opentenbase

# Verify the binary exists (it's a symlink to the official opentenbase_ctl)
ls -la /usr/bin/opentenbase-ctl
ls -la /usr/lib/opentenbase/5.0/bin/opentenbase_ctl
```

### `error while loading shared libraries: libpqxx-6.4.so`

**Cause**: The `libpqxx` runtime library is missing. This was fixed in v5.0-p30 (library is now bundled).

**Solution**:

```bash
# Check if the library is bundled
ls -la /usr/lib/opentenbase/5.0/lib/libpqxx*

# If missing, install from system or upgrade to v5.0-p31+
sudo apt install -y libpqxx-dev  # DEB
sudo dnf install -y libpqxx-devel  # RPM
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
**Last Updated**: 2026-06-29 (v5.0-p32, GTM 2-core fix + CN port 11003)
