# OpenTenBase-Packages 改进计划

> **状态：已归档** — 本计划已完成，内容合并至 [ROADMAP.md](../ROADMAP.md)。
> 如需查看历史规划，请保留本文档。

> 创建时间：2026-05-21
> 维护者：muzimu217

## 阶段一：仓库结构重构与基础完善

### 任务清单

| 任务 | 优先级 | 工作量 | 状态 | 说明 |
|------|--------|--------|------|------|
| 1.1 仓库结构重构 | P0 | 4h | ✅ 已完成 | 整理根目录遗留文件 |
| 1.2 Docker Compose | P0 | 8h | 已完成 | 一键集群部署 |
| 1.3 测试脚本 | P0 | 4h | 已完成 | smoke-test + integration-test |
| 1.4 CI 测试 | P1 | 2h | 已完成 | test.yml 工作流 |
| 1.5 DevContainer | P1 | 2h | 已完成 | VSCode 开发容器 |

### 1.1 仓库结构重构

**目标结构：**

```
OpenTenBase-Packages/
├── .devcontainer/          # VSCode DevContainer 配置
├── .github/workflows/      # CI/CD 工作流
├── config/                 # 配置文件模板（新增）
│   ├── opentenbase.conf
│   ├── opentenbase-ctl
│   ├── gtm.conf.template
│   ├── pg_hba.conf.template
│   ├── postgresql.conf.coord.template
│   └── postgresql.conf.dn.template
├── debian/                 # Debian 打包元数据
│   ├── changelog
│   ├── control
│   ├── copyright
│   ├── rules
│   ├── source/
│   ├── *.install
│   ├── *.lintian-overrides
│   ├── *.postinst
│   ├── *.prerm
│   ├── *.postrm
│   ├── *.dirs
│   ├── *.docs
│   └── not-installed
├── docker/
│   ├── build/              # 构建用 Dockerfile
│   ├── compose/            # Docker Compose 部署
│   └── runtime/            # 运行时 Dockerfile
├── docs/                   # 文档
├── patches/                # 源码补丁
├── scripts/                # 脚本工具
├── systemd/                # systemd 服务文件
└── test/                   # 测试脚本
```

**执行步骤：**

1. 创建 `refactor/structure` 分支
2. 创建 `config/` 目录
3. 移动根目录配置文件到 `config/`
4. 移动打包元数据到 `debian/`
5. 创建 `docker/runtime/` 目录
6. 更新 CI 配置中的路径引用
7. 本地测试构建
8. 提交并创建 PR

**风险控制：**

- 在分支上操作，不影响 main
- 每次移动后检查 CI 路径引用
- 先本地测试，再提交

### 1.2 Docker Compose（已完成）

- `docker/compose/docker-compose.yml` - 一键集群部署
- `docker/compose/Dockerfile.runtime` - 运行时镜像
- `docker/compose/entrypoint.sh` - 容器入口脚本
- `docker/compose/README.md` - 使用说明

### 1.3 测试脚本（已完成）

- `test/smoke-test.sh` - 冒烟测试（安装验证）
- `test/integration-test.sh` - 集成测试（SQL 操作验证）

### 1.4 CI 测试（已完成）

- `.github/workflows/test.yml` - 自动化测试工作流
- 支持 5 个发行版的安装测试
- 支持集群初始化和 SQL 查询测试

### 1.5 DevContainer（已完成）

- `.devcontainer/devcontainer.json` - VSCode 配置
- `.devcontainer/Dockerfile` - 开发容器镜像
- `.devcontainer/setup.sh` - 环境初始化脚本

---

## 仓库整合迁移（已完成）

> 将 Docker 集群部署方案从 opentenbase-dev 迁移到 opentenbase-deb，实现单一仓库包含所有部署能力。

### 迁移内容

- Docker 集群部署文件（Dockerfile.centos, setup.sh, config.ini, postgres.conf）
- RPM 打包目录结构
- 清理注释中的"参考官方"字样

### 已完成验证

- [x] Docker 集群在 EulerOS aarch64 上构建成功
- [x] 4 节点集群启动正常（GTM + CN + 2DN）
- [x] CRUD 测试通过（25/28）
- [x] RPM 实测：7/7 发行版通过（CI run 26510778148）

---

## 阶段二：功能增强

| 任务 | 优先级 | 工作量 | 状态 |
|------|--------|--------|------|
| 2.1 APT 仓库 | P0 | 4h | ✅ 已完成（GitHub Pages APT/RPM repo, GPG signed, 多版本 component 索引） |
| 2.2 多架构支持 | P1 | 8h | ✅ 已完成（x86_64: 15 发行版全通过；aarch64: openEuler 22.03 已验证，Rocky/Alma ARM64 待修复） |
| 2.3 版本升级自动化 | P1 | 4h | ✅ 已完成（自动发布工作流） |
| 2.4 监控集成 | P2 | 4h | Deferred |
| 2.5 多版本管理 | P1 | 16h | ✅ 已完成 |

### 2.2 多架构支持（已完成）

- x86_64: 15 个发行版全部通过（DEB 7 + RPM 8）
- aarch64: openEuler 22.03 已验证（hdspace 实测，4vCPU 7.2GB）
- ARM64 CI 仅构建 openEuler，Rocky/Alma ARM64 有 QEMU 依赖问题待修复

### 2.3 版本升级自动化（已完成）

- `.github/workflows/publish.yml` 自动发布工作流
- `.github/workflows/test-all.yml` 全发行版测试工作流
- install.sh TAG 修复完成
- ensure_dirs 修复完成

### 2.5 多版本管理（已完成）

- 版本化安装前缀：`/usr/lib/opentenbase/5.0/`
- 版本化配置：`/etc/opentenbase/5.0/`
- 版本化数据目录：`/var/lib/opentenbase/5.0/`
- 符号链接切换机制：`/etc/opentenbase/current`
- `opentenbase-switch-version` 版本切换命令
- `--version` 安装参数支持
- version-switch-test 脚本已集成到 CI
- 多版本管理文档已合并到 README.md

---

## 参考链接

- 仓库地址：https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages
- 最新 Release：https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/tag/v5.0-p9
- 上游仓库：https://github.com/OpenTenBase/OpenTenBase

**Update 2026-06-01:** Multi-version end-to-end verification completed on real ARM64 hardware (DevEnvVM, HCE 2.0, 4vCPUs, 8GB). All three versions (v5.0, v2.6.0, v2.5.0) verified: init → start → SQL query → stop → switch. Fixed max_pool_size >= max_connections and forward_port version-conditional issues.
