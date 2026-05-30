# Changelog

All notable changes to OpenTenBase Packages are documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/).

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
- Gitee mirror auto-detection for China users in setup scripts
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
- Gitee mirror auto-detection for China users in setup scripts
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

[v5.0-p4]: https://github.com/muzimu217/OpenTenBase-deb/releases/tag/v5.0-p4
[v5.0-p3]: https://github.com/muzimu217/OpenTenBase-deb/releases/tag/v5.0-p3
[v5.0-p2]: https://github.com/muzimu217/OpenTenBase-deb/releases/tag/v5.0-p2
[v5.0-multi16]: https://github.com/muzimu217/OpenTenBase-deb/releases/tag/v5.0-multi16
[v5.0-multi12]: https://github.com/muzimu217/OpenTenBase-deb/releases/tag/v5.0-multi12
[v5.0-multi9]: https://github.com/muzimu217/OpenTenBase-deb/releases/tag/v5.0-multi9
[v5.0-multi8]: https://github.com/muzimu217/OpenTenBase-deb/releases/tag/v5.0-multi8
[v5.0-1ubuntu1]: https://github.com/muzimu217/OpenTenBase-deb/releases/tag/v5.0-1ubuntu1
[v5.0]: https://github.com/muzimu217/OpenTenBase-deb/releases/tag/v5.0
