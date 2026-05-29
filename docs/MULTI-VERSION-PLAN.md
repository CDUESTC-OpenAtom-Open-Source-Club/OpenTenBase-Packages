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

| 版本 | DEB/RPM 包 | CI 构建 | 仓库发布 | EulerOS 源码测试 |
|------|:---:|:---:|:---:|:---:|
| **v5.0** | 有 (50个) | 有 | v5.0-p2 | 通过 |
| **v2.6.0** | 无 | 无 | 无 | 通过 (手动编译) |
| **v2.5.0** | 无 | 无 | 无 | 通过 (手动编译) |

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

### Step 1: 修改 build-deb.yml — 添加版本模板替换

在 "Build DEB packages" 步骤中，在 `cp debian/` 之后、`debian/rules binary` 之前，添加 sed 替换：

```bash
if [ "$OTB_VERSION" != "5.0" ]; then
    find debian/ -type f -exec sed -i "s/5\.0/$OTB_VERSION/g" {} +
fi
```

### Step 2: 修改 build-deb.yml / build-rpm.yml — 支持多版本矩阵

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

### Step 5: 运行 CI 构建

触发 build-deb.yml 和 build-rpm.yml，构建三个版本的包。

### Step 6: 创建新 Release

创建 `v5.0-p3` release，上传所有三个版本的包。

### Step 7: 验证 APT/RPM 仓库

在 Docker 容器中测试三个版本的安装、切换、独立运行。

### Step 8: 更新文档

更新 docs/README.md 和 README_zh.md，添加多版本安装说明。

### Step 9: 运行 test-all.yml

跨发行版验证所有版本。

## 用户体验

### DEB (Ubuntu/Debian)

```bash
# 一键配置仓库
curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-apt.sh | sudo bash
sudo apt update

# 安装最新版 (v5.0)
sudo apt install opentenbase

# 或安装指定版本
sudo apt install opentenbase-2.6.0
sudo apt install opentenbase-2.5.0

# 切换版本
sudo opentenbase-switch-version 2.6.0
```

### RPM (RHEL/CentOS/Fedora)

```bash
# 一键配置仓库
curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-rpm.sh | sudo bash

# 安装最新版 (v5.0)
sudo dnf install opentenbase

# 或安装指定版本
sudo dnf install opentenbase-2.6.0
sudo dnf install opentenbase-2.5.0
```

## 验证清单

- [ ] build-deb.yml 支持 version: ['5.0', '2.6.0', '2.5.0']
- [ ] build-rpm.yml 支持 version: ['5.0', '2.6.0', '2.5.0']
- [ ] v2.6.0 DEB 构建成功 (7 个发行版)
- [ ] v2.5.0 DEB 构建成功 (7 个发行版)
- [ ] v2.6.0 RPM 构建成功 (8 个发行版)
- [ ] v2.5.0 RPM 构建成功 (8 个发行版)
- [ ] v5.0-p3 release 创建，包含 150+ DEB + 24 RPM
- [ ] APT 仓库可安装三个版本
- [ ] RPM 仓库可安装三个版本
- [ ] opentenbase-switch-version 可切换三个版本
- [ ] 各版本 init/start/SQL 测试通过
- [ ] 文档更新完成
- [ ] test-all.yml 14/14 通过

## 时间线

| 阶段 | 内容 | 预计 |
|------|------|------|
| Phase 1 | 修改 CI workflow + 配置模板 | 1 小时 |
| Phase 2 | 运行构建 + 创建 Release | 30 分钟 |
| Phase 3 | 验证 + 测试 | 30 分钟 |
| Phase 4 | 文档更新 | 15 分钟 |
