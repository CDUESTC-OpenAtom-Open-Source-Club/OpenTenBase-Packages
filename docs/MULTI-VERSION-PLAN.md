# 多版本 DEB/RPM 打包计划 — v5.0 + v2.6.0 + v2.5.0

## 目标

三个版本都做成完整的 DEB/RPM 包，发布到同一个 APT/RPM 仓库，用户可以：

```bash
sudo apt install opentenbase          # 安装最新 v5.0
sudo apt install opentenbase-2.6.0    # 安装 v2.6.0
sudo apt install opentenbase-2.5.0    # 安装 v2.5.0
opentenbase-switch-version 2.6.0      # 切换版本
```

## 当前状态

| 版本 | DEB 包 (7 发行版) | RPM 包 (8 发行版) | CI 构建 | Release 发布 | CI 测试 | APT/RPM 仓库 |
|------|:---:|:---:|:---:|:---:|:---:|:---:|
| **v5.0** | ✅ 42 个 | ✅ 8+ 个 | ✅ | v5.0-p3 | ✅ 14/14 发行版 | ✅ component: main |
| **v2.6.0** | ✅ 42 个 | ✅ 8+ 个 | ✅ | v5.0-p3 | ✅ test-all.yml 矩阵 | ✅ component: v2.6 |
| **v2.5.0** | ✅ 42 个 | ✅ 8+ 个 | ✅ | v5.0-p3 | ✅ test-all.yml 矩阵 | ✅ component: v2.5 |

> **更新于 2026-05-31**：APT 仓库使用 component 作为版本选择器（main=v5.0, v2.6=v2.6.0, v2.5=v2.5.0），
> 每个 component 有独立的 pool/ 和 Packages 文件，解决了 dpkg-scanpackages 按包名去重的问题。
> RPM 仓库由 createrepo_c 原生支持多版本。CI 测试矩阵已支持三个版本。

## 核心问题

当前所有打包文件中版本号 `5.0` 是硬编码的：

| 文件 | 硬编码位置 | 影响 |
|------|-----------|------|
| `debian/rules` | `OTB_VERSION := 5.0` | 构建路径 (CI 已用 sed 覆盖) |
| `debian/opentenbase-server.install` | `usr/lib/opentenbase/5.0/bin/...` | 安装文件列表 |
| `debian/opentenbase-client.install` | `usr/lib/opentenbase/5.0/bin/...` | 安装文件列表 |
| `debian/opentenbase-server.dirs` | `usr/lib/opentenbase/5.0/lib/postgresql` | 创建目录 |
| `debian/opentenbase-server.postinst` | `OTB_VERSION="5.0"` | 安装后脚本 |
| `debian/opentenbase-client.postinst` | `/usr/lib/opentenbase/5.0/bin/psql` | alternatives 注册 |
| `debian/opentenbase-client.prerm` | `/usr/lib/opentenbase/5.0/bin/psql` | alternatives 移除 |

RPM 侧使用 `%{otb_ver}` 宏，已天然支持多版本。

## 方案：构建时模板替换

在 CI 构建时，用 `sed` 将所有 `5.0` 替换为目标版本。不需要修改源文件，只需要在 CI workflow 中添加替换步骤。

## 实施步骤

### Step 1: 修改 build-deb.yml — 添加版本模板替换 ✅

在 "Build DEB packages" 步骤中，在 `cp debian/` 之后、`debian/rules binary` 之前，添加 sed 替换：

```bash
if [ "$OTB_VERSION" != "5.0" ]; then
    find debian/ -type f -exec sed -i "s/5\.0/$OTB_VERSION/g" {} +
fi
```

> **注意**：PR #5 已将 blanket `s/5.0/.../g` 改为精确锚定匹配，避免误替换注释。

### Step 2: 修改 build-deb.yml / build-rpm.yml — 支持多版本矩阵 ✅

将两个 workflow 改为支持 version × distro 的二维矩阵：

```yaml
matrix:
  version: ['5.0', '2.6.0', '2.5.0']
  include:
    - name: ubuntu-20.04-amd64
      container: ubuntu:20.04
      codename: focal
    # ... 其他发行版
```

### Step 3: 创建 v2.6.0 和 v2.5.0 的配置模板

v2.6.0/v2.5.0 不支持 `forward_port` 参数，需要创建不含该参数的配置文件：

- `config/v2.6.0/opentenbase.conf`
- `config/v2.5.0/opentenbase.conf`

在 `debian/rules` 的 `override_dh_auto_install` 中，根据 OTB_VERSION 选择对应的配置文件。

### Step 4: 处理 v2.6.0/v2.5.0 的构建差异

| 差异点 | v5.0 | v2.6.0 / v2.5.0 |
|--------|------|-----------------|
| forward_port 配置 | 支持 | 不支持 |
| 节点组语法 | DISTRIBUTE BY SHARD | CREATE DEFAULT NODE GROUP |
| 部分 contrib 模块 | 完整 | 可能缺少部分 |

### Step 5: 运行 CI 构建 ✅

触发 build-deb.yml 和 build-rpm.yml，构建三个版本的包。

### Step 6: 创建新 Release ✅

创建 `v5.0-p3` release，上传 154 个包（3 版本 × 15 发行版 × 6 包名 + src RPM）。

### Step 7: 验证 APT/RPM 仓库 ❌

在 Docker 容器中测试三个版本的安装、切换、独立运行。

> **未完成原因**：APT/RPM 仓库只索引 v5.0。需要独立包名（`opentenbase-2.6.0`）才能实现多版本共存安装。

### Step 8: 更新文档

更新 docs/README.md 和 README_zh.md，添加多版本安装说明。

### Step 9: 运行 test-all.yml

跨发行版验证所有版本。

## 用户体验

### DEB (Ubuntu/Debian)

```bash
# 一键配置仓库 (默认安装 v5.0)
curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-apt.sh | sudo bash
sudo apt install opentenbase

# 安装指定版本 (通过 --version 参数)
curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-apt.sh | sudo bash -s -- --version 2.6.0
sudo apt install opentenbase

# APT 组件与版本对应关系:
#   main = v5.0 (最新)
#   v2.6 = v2.6.0
#   v2.5 = v2.5.0
#
# 也可以手动编辑 sources.list 切换 component:
#   deb [signed-by=...] https://apt.blackevil217.com/apt jammy v2.6

# 切换已安装版本
sudo opentenbase-switch-version 2.6.0
```

### RPM (RHEL/CentOS/Fedora)

```bash
# 一键配置仓库
curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-rpm.sh | sudo bash

# 安装最新版 (v5.0)
sudo dnf install opentenbase

# 安装指定版本
sudo dnf install opentenbase-2.6.0
sudo dnf install opentenbase-2.5.0
```

## 验证清单

### 已完成

- [x] build-deb.yml 支持 version: ['5.0', '2.6.0', '2.5.0']
- [x] build-rpm.yml 支持 version: ['5.0', '2.6.0', '2.5.0']
- [x] v2.6.0 DEB 构建成功 (7 个发行版)
- [x] v2.5.0 DEB 构建成功 (7 个发行版)
- [x] v2.6.0 RPM 构建成功 (8 个发行版)
- [x] v2.5.0 RPM 构建成功 (8 个发行版)
- [x] v5.0-p3 release 创建，包含 154 个包 (126 DEB + 24+ RPM + src)
- [x] APT 仓库多版本索引 — 使用 component 作为版本选择器 (main/v2.6/v2.5)
- [x] RPM 仓库多版本索引 — createrepo_c 原生支持
- [x] v2.6.0/v2.5.0 CI 测试 — test-all.yml 矩阵支持三个版本
- [x] 文档更新

### 部分完成

- [x] 多版本文件共存验证 — DevEnvVM (HCE 2.0 ARM64) 上 3 个版本 (2.5.0, 2.6.0, 5.0) 文件共存正常
- [x] 各版本独立 init/start/SQL 验证 — v5.0 在 Ubuntu 24.04 和 HCE 2.0 上端到端通过
- [ ] opentenbase-switch-version 端到端验证 — 未在同一系统上做过完整的版本切换 + init/start/SQL 测试

## 时间线

| 阶段 | 内容 | 预计 |
|------|------|------|
| Phase 1 | 修改 CI workflow + 配置模板 | 1 小时 |
| Phase 2 | 运行构建 + 创建 Release | 30 分钟 |
| Phase 3 | 验证 + 测试 | 30 分钟 |
| Phase 4 | 文档更新 | 15 分钟 |
