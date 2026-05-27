# OpenTenBase-deb 改进计划

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
OpenTenBase-deb/
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

## 阶段二：功能增强

| 任务 | 优先级 | 工作量 | 状态 |
|------|--------|--------|------|
| 2.1 APT 仓库 | P0 | 4h | 待开始（超出当前范围） |
| 2.2 多架构支持 | P1 | 8h | ✅ 已完成（x86_64 + aarch64 双架构，CI 14/14 通过） |
| 2.3 版本升级自动化 | P1 | 4h | ✅ 已完成（自动发布工作流） |
| 2.4 监控集成 | P2 | 4h | 待开始（超出当前范围） |
| 2.5 多版本管理 | P1 | 16h | ✅ 已完成 |

### 2.2 多架构支持（已完成）

- x86_64 和 aarch64 双架构构建
- CI 验证：14/14 发行版全部通过（run 26510778148）
- DEB: Ubuntu 22.04/24.04, Debian 11/12 (amd64 + arm64)
- RPM: CentOS 8/9, Fedora 39/40, openEuler 22.03/24.03, EulerOS (x86_64)

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
- 文档：`docs/VERSION-MANAGEMENT.md`

---

## 参考链接

- 仓库地址：https://github.com/muzimu217/OpenTenBase-deb
- 最新 Release：https://github.com/muzimu217/OpenTenBase-deb/releases/tag/v5.0-multi10
- 上游仓库：https://github.com/OpenTenBase/OpenTenBase
