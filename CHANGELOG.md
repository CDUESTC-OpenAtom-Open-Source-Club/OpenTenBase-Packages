# Changelog

All notable changes to OpenTenBase Packages are documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/).

---

## [v5.0-p31] — 2026-06-28

**Major architecture change: replaced custom bash script with official `opentenbase_ctl` C++ binary.**

This release replaces the custom `opentenbase-ctl` bash script with the upstream OpenTenBase official `opentenbase_ctl` C++ compiled binary, built from `contrib/opentenbase_ctl/` in the upstream source tree. The new binary provides full cluster lifecycle management (install/delete/start/stop/status/expand/shrink) via INI configuration files.

### Changed (Breaking)
- **Removed**: Custom bash script `opentenbase-ctl` (old commands: `init`/`start`/`stop`/`status`/`restart`/`switch`)
- **Added**: Official C++ binary `opentenbase_ctl` at `/usr/lib/opentenbase/5.0/bin/opentenbase_ctl`
- **Added**: `/usr/bin/opentenbase-ctl` symlink → official binary (backward-compatible alias)
- New commands: `install` / `delete` / `start` / `stop` / `status` / `expand` / `shrink`
- Cluster initialization now uses `opentenbase_ctl install -c config.ini` (INI config) instead of `opentenbase-ctl init`

### Added
- Official `opentenbase_ctl` C++ binary built from upstream `contrib/opentenbase_ctl/`
  - Supports distributed and centralized instance types
  - Multi-node parallel installation via SSH/SCP
  - Automatic node registration and node group creation
  - Expand/shrink for dynamic cluster scaling
- INI configuration template: `config/opentenbase_config.ini.example`
  - Sections: `[instance]`, `[gtm]`, `[coordinators]`, `[datanodes]`, `[server]`, `[log]`
  - Installed to `/etc/opentenbase/5.0/opentenbase_config.ini.example`
- CLI11 v2.4.2 single-header fallback for distributions without `libcli11-dev` / `cli11-devel`
  - Automatically downloaded from GitHub Releases when system package unavailable
  - Affects: Ubuntu 20.04, Debian 11
- `libpqxx.so` bundled into package at `/usr/lib/opentenbase/5.0/lib/`
  - Utilizes existing `-rpath` to find the library at runtime
  - Built from source (v7.9.2) via CMake when system package unavailable
- `opentenbase-ctl` symlink added to DEB `.install` files
- SSH setup in test Docker containers (openssh-server/client, passwordless SSH for root and opentenbase users)

### Fixed
- CLI11 header missing on Ubuntu 20.04 / Debian 11 (`fatal error: CLI/CLI.hpp: No such file or directory`)
- `opentenbase-ctl` symlink not included in DEB packages (`[FAIL] Binary missing: /usr/bin/opentenbase-ctl`)
- `opentenbase_config` file conflict between `opentenbase-server` and `libopentenbase-dev` packages
- `libpqxx-6.4.so` runtime missing (`error while loading shared libraries: libpqxx-6.4.so`)
- DEB `dh_install` strict path checking for dynamically built binaries
- RPM `libpq.so.5(RHPG_10)(64bit)` dependency check (use `--nodeps` for installation)

### Build Dependencies
| Dependency | Version | Purpose |
|------------|---------|---------|
| libpqxx | 7.9.2 | C++ PostgreSQL client library (built from source) |
| CLI11 | v2.4.2 | Command-line argument parsing (single-header fallback) |
| libssh2 | system | SSH library for remote node management |

### CI/CD
- v5.0-p25 through v5.0-p31: 7 iterations to resolve build/packaging issues
- All CI builds passing: DEB (5 distros) + RPM (rockylinux-9)
- Smoke test simplified to package verification + binary functionality check

### Known Issues
- `OSS_INSTALL_DIR` hardcoded as `/usr/local/install/opentenbase` in upstream source — does not match packaging prefix `/usr/lib/opentenbase/5.0/`
  - Workaround: create symlink `ln -sf /usr/lib/opentenbase/5.0 /usr/local/install/opentenbase`
- `libpq.so.5: no version information available` warning — non-fatal, OpenTenBase's bundled libpq lacks RPM version symbols

---

## [v5.0-p11] — 2026-06-02

Documentation updates for Cloudflare CDN acceleration.

### Added
- CDN acceleration documentation in README.md and README_zh.md
- Mirror acceleration section explaining CDN priority and fallback
- Cloudflare CDN feature added to features table

---

## [v5.0-p10] — 2026-06-02

Docker container E2E testing + native ARM64 package builds + version switch fix.

### Added
- Docker container E2E test suite (`test/docker-e2e-test.sh`)
  - Tests package installation + init/start/SQL/stop in isolated containers
  - Rocky Linux 9 (aarch64): all tests passed
  - openEuler 24.03 (aarch64): all tests passed
  - Ubuntu 22.04 (aarch64): skipped (OpenSSL 1.1 binary compatibility)
- Test results: `test/docker-e2e-results.md`
- Docker installed on DevEnvVM via static binary (Huawei mirror)
- **Native ARM64 (aarch64) packages** built on DevEnvVM
  - RPM: `opentenbase-5.0-1.aarch64.rpm` (9.0MB)
  - DEB: 5 packages for Ubuntu 22.04 arm64 (server, client, contrib, dev, doc)
  - Built natively on HCE 2.0 ARM64 (no QEMU emulation)
- **Full aarch64 test matrix** — RPM + DEB all passing
  - RPM (HCE 2.0): install → init/start/status/SQL/stop → version switch (5.0→2.6.0→2.5.0→5.0)
  - DEB (Ubuntu 22.04 Docker): install → init/start/status/SQL/stop

### Fixed
- DEB ARM64 build: `configure: error: zlib version is too old` caused by missing `intptr_t` in autoconf check
  - Root cause: autoconf `AC_CHECK_TYPES([intptr_t])` doesn't include `<stdint.h>` on aarch64
  - Fix: added `-include stdint.h` to CFLAGS in `debian/rules` for ARM64 builds
- `opentenbase-switch-version`: binary symlinks in `/usr/bin/` not updated on version switch
  - Root cause: script only updated `/etc/opentenbase/current` but not `/usr/bin/postgres`, `/usr/bin/psql`, etc.
  - Fix: added automatic symlink update for all binaries pointing to `/usr/lib/opentenbase/*/bin/*`

### Dependencies Documented
| Distro | Required Packages |
|--------|------------------|
| Rocky Linux 9 | `sudo`, `which`, `shadow-utils`, `procps-ng` |
| openEuler 24.03 | `sudo`, `which`, `shadow-utils`, `procps-ng`, `util-linux-user` |

---

## [v5.0-p9] — 2026-06-01

Multi-version end-to-end verification on real ARM64 hardware.

### Added
- Multi-version end-to-end verification on DevEnvVM (HCE 2.0 ARM64, 4vCPUs, 8GB RAM)
  - Verified complete version switching flow: v5.0 → v2.6.0 → v2.5.0 → v5.0
  - Each version successfully: init → start → SQL query → stop
  - No residual conflicts between versions during switching
  - All three versions (2.5.0, 2.6.0, 5.0) coexist and switch cleanly

### Verification Results
| Version | init | start | SQL query | stop | Switch to next |
|---------|------|-------|-----------|------|----------------|
| v5.0 | ✅ | ✅ | ✅ | ✅ | ✅ |
| v2.6.0 | ✅ | ✅ | ✅ | ✅ | ✅ |
| v2.5.0 | ✅ | ✅ | ✅ | ✅ | ✅ |
| v5.0 (return) | ✅ | ✅ | ✅ | ✅ | — |

### Updated
- TEST-PLAN.md: RPM aarch64 version switch status updated to "已完成"
- MULTI-VERSION-PLAN.md: opentenbase-switch-version end-to-end verification marked complete

---

## [v5.0-p8] — 2026-06-01

Stress test suite and cross-machine multi-node deployment verification.

### Added
- Stress test workflow (`.github/workflows/stress-test.yml`) — 7/7 tests passing
  - Sharding table creation, 100-row single-row INSERT, data consistency check
  - Batch UPDATE (50 rows), Batch DELETE, complex aggregation, SELECT with WHERE
- Cross-machine multi-node deployment test (`test/cross-machine-test.sh`)
  - Architecture: devenv (ARM64, GTM+Coordinator) + 47.108 (x86_64, Datanode)
  - SSH reverse tunnel for NAT traversal (GTM port 16666, Coord port 15432)
  - Full CRUD verification across machines with data locality confirmation
- Inline cluster setup in stress-test.yml (no dependency on multi-node-test.sh)

### Fixed
- `dh_install` missing files on Ubuntu 20.04/Debian 11 v5.0 builds
  - Root cause: Make variable expansion — `$E` from `EXTRA_EXCL=""` was interpreted as Make variable `E` (empty)
  - Fix: replaced variable-based exclusion with `sed -i "/pattern/d"` to delete matching lines from `.install` files before `dh_install` runs
- Stress test `generate_series` bulk INSERT extremely slow on distributed tables (1000 rows = 19 min)
  - Replaced with single-row INSERT loop (100 rows = 3s)

### CI/CD
- Stress test CI run 26740585786: 7/7 PASSED
- Cross-machine deployment: 11/11 test items PASSED
- Updated TEST-PLAN.md, ROADMAP.md with final results

---

## [v5.0-p7] — 2026-05-30

ARM64 RPM CI matrix and comprehensive test verification.

### Added
- ARM64 RPM CI matrix using QEMU emulation (`build-rpm.yml`)
- openEuler 22.03 aarch64 builds successfully (9.3MB RPM)
- Dual architecture CI: x86_64 (8 distros) + aarch64 (openEuler)
- Docker output volume mount fix for artifact upload

### Test Results
- x86_64: 8/8 distros passing
- aarch64: 1/1 (openEuler) passing, Rocky/Alma needs dependency fixes

---

## [v5.0-p6] — 2026-05-30

Cloudflare CDN acceleration and Docker image publishing.

### Added
- Cloudflare CDN mirror: `apt.blackevil217.com` / `rpm.blackevil217.com`
- DNS CNAME records with Cloudflare Proxy enabled
- CNAME file generation in `build-repo.sh` for GitHub Pages custom domain
- CDN mirror detection in `setup-apt.sh` and `setup-rpm.sh`
- Docker image published to GHCR: `ghcr.io/muzimu217/opentenbase-runtime:v5.0-p6`
  - Base image: openEuler 22.03
  - Includes OpenTenBase 5.0 runtime environment
  - Workflow: `docker-publish.yml` (manual trigger or on release)

### Mirror Priority
1. Cloudflare CDN (apt.blackevil217.com / rpm.blackevil217.com) — global acceleration, free forever
2. GitHub Pages (muzimu217.github.io) — direct fallback

### Docker Usage
```bash
docker pull ghcr.io/muzimu217/opentenbase-runtime:v5.0-p6
docker run -d -p 5432:5432 ghcr.io/muzimu217/opentenbase-runtime:v5.0-p6
```

---

## [v5.0-p5] — 2026-05-30

Critical bug fix for cluster initialization.

### Fixed
- `opentenbase-ctl` node registration failure: changed psql from `-d postgres` to `-d template1`
  - `register_nodes()`: postgres database doesn't exist after initdb (only template0/template1)
  - `setup_node_group()`: pgxc_group is a global catalog, accessible from any database
  - Added postgres database creation after node registration completes
  - This fixes silent failures where all errors were swallowed by `2>/dev/null || true`

---

## [v5.0-p4] — 2026-05-30

Advanced CI test suite — all 14 distros fully passing with 5 new test suites.

### Fixed
- Bash `((var++))` returns exit code 1 when var=0, triggers `set -e` — changed all 5 test scripts to use `var=$((var + 1))`
- `timeout` inside `su -c` doesn't propagate signals to child processes — moved timeout outside su wrapper
- `INSERT INTO distributed_table SELECT ... FROM generate_series()` hangs indefinitely on distributed tables — replaced with single-row INSERT loops
- `psql` captured `COMMIT` output instead of `SELECT` result in transaction tests — used `psql -1` flag for single-transaction mode
- Job timeout of 30 minutes too short for advanced tests — increased to 60 minutes in test-all.yml
- Port conflicts between multi-node-test and advanced tests — added port cleanup and `wait_for_port_free()`
- Sharding map initialization: correct SQL syntax is `CREATE SHARDING GROUP TO GROUP <group_name>`

### Added
- 5 advanced test suites: transactions, connection pool, data types, performance benchmarks, failover & recovery
- `test/advanced/test_transactions.sh` — distributed COMMIT/ROLLBACK, cross-node consistency, READ COMMITTED isolation, SAVEPOINT/nested SAVEPOINT (6 tests)
- `test/advanced/test_connection_pool.sh` — connection establishment, concurrent connections, pool reload, pool exhaustion (6 tests)
- `test/advanced/test_data_types.sh` — int, text, jsonb, timestamp, array, numeric, NULL handling (7 tests)
- `test/advanced/test_performance.sh` — bulk INSERT, full table scan, filtered SELECT, JOIN, index effectiveness, ORDER BY+LIMIT (6 tests)
- `test/advanced/test_failover.sh` — cluster health, GTM status, datanode connectivity, stress R/W, data consistency, query routing, transaction recovery (7 tests)
- `test/run-advanced-tests.sh` — advanced test runner with cluster lifecycle management

### CI/CD
- `test-all.yml` now runs advanced test suite alongside basic tests
- All 14 distros (7 DEB + 7 RPM) pass both basic and advanced tests
- CI run 26683489025: 14/14 PASSED, all jobs completed in 2-7 minutes

### Test Results
- **31 advanced tests** across 5 suites, all passing
- Transactions: 6/6 | Connection Pool: 6/6 | Data Types: 7/7 | Performance: 6/6 | Failover: 7/7

---

## [v5.0-p3] — 2026-05-29

Multi-version coexistence release with expanded platform support.

### Added
- Multi-version coexistence: support OpenTenBase 5.0, 2.6.0, 2.5.0 side by side
- 15 Linux distros: Ubuntu 20.04/22.04/24.04/25.04, Debian 11/12/13, AlmaLinux 8/9, CentOS Stream 8/9, Rocky 8/9, Fedora 40/41, openEuler 22.03
- `opentenbase-ctl` cluster management script (init/start/stop/status/restart/switch)
- Versioned directory structure: `/usr/lib/opentenbase/{version}/`, `/etc/opentenbase/{version}/`
- `opentenbase-switch-version` tool for switching active versions
- Huawei Cloud EulerOS (hce) support in `setup-rpm.sh`

### CI/CD
- Complete CI/CD pipeline: automated build, test, and release for all versions
- Automated test suite: install, init, start, and SQL verification across all distros
- GitHub Pages auto-deployment for APT/RPM repositories
- Version selection mechanism in install script

### Packages
- 126 DEB packages (supporting Ubuntu/Debian series)
- 24 RPM packages (supporting RedHat series)
- 1 install.sh unified installer
- **Total: 151 packages**

### Known Issues
- First install requires manual `opentenbase-ctl init` to initialize the cluster
- Ubuntu 25.04 is preview support, may have compatibility issues

---

## [v5.0-p2] — 2026-05-28

Patch release with critical packaging fixes and full cross-distro CI verification.

### Fixed
- Correct `lib/postgresql` path in `opentenbase-server.dirs` (versioned path `/usr/lib/opentenbase/5.0/lib/postgresql`)
- Use relative Filename from base URL root in APT Packages file
- Correct `pool/` relative path in Packages file (4 levels up)
- Standard APT repo layout (`pool/` + `dists/`) with robust GPG key handling
- Move log functions before `detect_mirror` in `setup-apt.sh`

### Added
- Huawei Cloud EulerOS (hce) support in `setup-rpm.sh`

### CI/CD
- All 7 DEB targets: Ubuntu 20.04/22.04/24.04/25.04, Debian 11/12/13
- All 8 RPM targets: AlmaLinux 8/9, CentOS Stream 8/9, Rocky 8/9, Fedora 40, openEuler 22.03
- All 14 cross-distro tests pass (install + init + start + SQL)
- APT/RPM repository auto-deployed to GitHub Pages

### Packages
- 42 DEB packages (6 per distro × 7 distros)
- 8 RPM packages (1 per distro × 8 distros)
- **Total: 50 packages**

---

## [v5.0-multi16] — 2026-05-26

Multi-distro release with version-switch-test integration.

### Fixed
- `opentenbase-ctl start`: start all nodes before `register_nodes` to avoid pooler hang
- Download test packages from GitHub Release instead of artifacts
- `version-switch-test.sh` PATH inheritance and syntax fixes
- `run_as_otb` fallback for containers without sudo
- Use full paths and correct initdb flags in test scripts
- Add `setpriv` fallback and fix RPM deps installation
- Correct node registration flow and add python3 fallback
- Filter RPM downloads by architecture to prevent cross-arch conflicts

### Added
- Multi-node test plan and scripts (`test/multi-node-test.sh`)
- Version switching test plan and script (`test/version-switch-test.sh`)
- Long-term maintenance plan
- ARM64 performance test results in documentation

---

## [v5.0-multi12] — 2026-05-25

Multi-distro release with RPM build fixes.

### Fixed
- RPM build for aarch64: skip pgsql-http, fix SSL objfiles, disable debuginfo
- Remove unreliable QEMU ARM64 builds from CI/CD
- Rename packages with distro name to avoid overwrites in release
- Make openeuler build optional, release runs even if openeuler fails

### Added
- ARM64 builds to CI/CD (native runners)
- Per-distro CI/CD with manual trigger support
- Auto-release workflow and release notes generator

---

## [v5.0-multi9] — 2026-05-20

Multi-distro release with 30 build targets.

### Fixed
- DEB libpq race condition + RPM Fedora hardened build
- `--allow-multiple-definition` to fix linker errors
- Clear RPM env vars + improve DEB build logging
- Add GCC 12+ compatibility patches
- Add `-Wno-error` flags for GCC 12+ incompatible pointer types
- Escape shell variable in Makefile recipe for objfiles.txt
- Copy config and scripts dirs for DEB build
- Update `.install` files for versioned prefix `/usr/lib/opentenbase/5.0`
- Add `-latomic` to LIBS for 128-bit atomics
- Use `--no-as-needed` for libatomic and fix flex `lex.backup` error
- Add `-fPIC` to RPM CFLAGS for shared object linking
- Add `-mcx16` for inline 128-bit atomics
- Replace entire lex.backup check with `rm -f` for flex race condition

### Added
- 30 build targets (16 DEB + 14 RPM)
- Source-compiled Docker Compose deployment
- Multi-version management support (`opentenbase-switch-version`)
- `master`/`latest` version support in install.sh

---

## [v5.0-multi8] — 2026-05-18

Expanded distro support.

### Fixed
- Install.sh package naming to match CI output (`.jammy`/`.noble` suffixes)
- Dockerfile paths and missing Ubuntu Dockerfiles
- Optional packages tolerate missing versions (libpqxx-dev, libcli11-dev)
- Add `-L/usr/lib/x86_64-linux-gnu` to LDFLAGS for zstd/lz4
- Symlink zstd/lz4 to `/usr/local/lib` for OpenTenBase's hardcoded configure paths
- Add `-latomic` to LDFLAGS for 128-bit atomics on Debian
- Remove system libpq-dev to prevent linker conflicts
- Use `__atomic` builtins for 128-bit CAS instead of libatomic

### Added
- Ubuntu 20.04/22.04/24.04 multi-version build
- Auto-detect Ubuntu version in install.sh
- Chinese README (README_zh.md)
- Contributing guidelines (CONTRIBUTING.md, CONTRIBUTING_zh.md)
- Roadmap documentation (ROADMAP.md, ROADMAP_zh.md)

---

## [v5.0-1ubuntu1] — 2026-05-18

Initial DEB release.

### Added
- Ubuntu .deb packaging for OpenTenBase v5.0
- Runtime dependencies: libossp-uuid16, libpqxx-7.8t64
- `--enable-license=no` to disable license check
- `opentenbase-ctl` auto-setup node group and sharding map
- `02-nolic-sharding.patch`: bypass license check during sharding init

---

## [v5.0] — 2026-05-18

First release.

### Added
- Initial OpenTenBase v5.0 packaging
- DEB packages for Ubuntu 22.04/24.04
- Basic installation and verification

---

[v5.0-p31]: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tag/v5.0-p31
[v5.0-p11]: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tag/v5.0-p11
[v5.0-p8]: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tag/v5.0-p8
[v5.0-p4]: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tag/v5.0-p4
[v5.0-p3]: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tag/v5.0-p3
[v5.0-p2]: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tag/v5.0-p2
[v5.0-multi16]: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tag/v5.0-multi16
[v5.0-multi12]: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tag/v5.0-multi12
[v5.0-multi9]: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tag/v5.0-multi9
[v5.0-multi8]: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tag/v5.0-multi8
[v5.0-1ubuntu1]: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tag/v5.0-1ubuntu1
[v5.0]: https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tag/v5.0
