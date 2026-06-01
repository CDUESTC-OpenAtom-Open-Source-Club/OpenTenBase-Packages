# OpenTenBase Packages

English | [中文](README_zh.md)

> **Official cross-platform package repository for OpenTenBase** — Enterprise-grade multi-format, multi-distro packaging and distribution for the OpenTenBase distributed SQL database.
>
> **[Quick Start Guide (快速开始)](QUICKSTART.md)** — 5 minutes to install and run.

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

---

## Quick Install

### APT Repository (Ubuntu / Debian) — Recommended

```bash
curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-apt.sh | sudo bash
sudo apt update
sudo apt install opentenbase
```

### YUM/DNF Repository (RHEL / CentOS / Fedora)

```bash
curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-rpm.sh | sudo bash
sudo dnf install opentenbase
```

### Manual Install

```bash
# Download from releases: https://github.com/muzimu217/OpenTenBase-deb/releases
# DEB: sudo apt install ./opentenbase_*.deb
# RPM: sudo dnf install ./opentenbase-*.rpm
```

### One-Click Deploy (Interactive)

```bash
curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-cluster.sh | sudo bash
```

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

| Distribution | Version | DEB | RPM |
|-------------|---------|:---:|:---:|
| Ubuntu | 20.04 / 22.04 / 24.04 / 25.04 | ✅ | — |
| Debian | 11 / 12 / 13 | ✅ | — |
| Rocky Linux | 8 / 9 | — | ✅ |
| AlmaLinux | 8 / 9 | — | ✅ |
| CentOS Stream | 8 / 9 | — | ✅ |
| Fedora | 40 | — | ✅ |
| openEuler | 22.03 | — | ✅ |

> **Total**: 15 distros, 150 packages per release (126 DEB + 24 RPM) — 3 versions × 15 distros
>
> **ARM64 Verified**: openEuler 22.03 aarch64 tested on hdspace cloud (4vCPU, 7.2GB RAM) — full cluster deployment, SQL connectivity, and distributed table operations confirmed.

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
curl -sLO https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/docker/test-docker.sh
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

**Recommendation**: Use pre-built packages for production and quick evaluation. Use source builds for development, debugging, and contributing to the project. See [source-build-guide.md](source-build-guide.md) for detailed source build instructions.

---

## Build from Source

### Docker Build (Recommended)

```bash
git clone https://github.com/muzimu217/OpenTenBase-deb.git
cd OpenTenBase-deb

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
OpenTenBase-deb/
├── .github/workflows/       # CI/CD pipelines
├── config/                  # Default configuration templates
├── debian/                  # DEB packaging rules
├── rpm/                     # RPM packaging rules
├── docker/                  # Docker build environments
├── scripts/                 # Build, release, signing scripts
├── systemd/                 # systemd service units
├── patches/                 # Source patches
├── test/                    # Automated tests
└── docs/                    # Documentation
```

---

## Release History

| Release | Date | Assets | Notes |
|---------|------|--------|-------|
| v5.0-p8 | 2026-06-01 | 150 | Stress test (7/7), cross-machine deployment, dh_install fix |
| v5.0-p3 | 2026-05-29 | 150 | Multi-version (5.0+2.6.0+2.5.0), 15 distros |
| v5.0-p2 | 2026-05-28 | 50 | Fix lib/postgresql path, all 15 distros |
| v5.0-multi16 | 2026-05-26 | 42 | Multi-distro release (DEB + RPM) |
| v5.0-multi12 | 2026-05-25 | 31 | Multi-distro release (DEB + RPM) |
| v5.0-multi9 | 2026-05-20 | 31 | Multi-distro release (DEB + RPM) |
| v5.0 | 2026-05-18 | 7 | First release |

See [GitHub Releases](https://github.com/muzimu217/OpenTenBase-deb/releases) for all releases.

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

## Contributing

Contributions are welcome — code, bug reports, and improvement suggestions!

1. Fork this repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit and push your changes
4. Create a Pull Request

See [Contributing Guide](CONTRIBUTING.md) for details.

---

## License

Same as OpenTenBase — [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

---

## Links

| Resource | Link |
|----------|------|
| **This project** | https://github.com/muzimu217/OpenTenBase-deb |
| **Upstream repo** | https://github.com/OpenTenBase/OpenTenBase |
| **OpenTenBase docs** | https://github.com/OpenTenBase/OpenTenBase/wiki |
| **Issue tracker** | [Issues](https://github.com/muzimu217/OpenTenBase-deb/issues) |

---

**Maintainer**: muzimu217
**Last Updated**: 2026-06-01 (v5.0-p8, stress test + cross-machine deployment)
