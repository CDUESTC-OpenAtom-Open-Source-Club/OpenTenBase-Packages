# OpenTenBase .deb 打包

[English](README.md) | 中文

Ubuntu .deb 打包方案，用于 [OpenTenBase](https://github.com/OpenTenBase/OpenTenBase) v5.0（基于 PostgreSQL 10 的分布式 SQL 数据库）。

## 快速安装

### 一键安装（推荐）

```bash
# 下载并运行安装脚本
curl -sLO https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi8/install.sh
sudo bash install.sh
```

安装脚本会自动：
- 检测 Ubuntu 版本（22.04 或 24.04）
- 下载对应的 .deb 软件包
- 通过 apt 解决依赖关系

### 手动安装

```bash
# 对于 Ubuntu 24.04 (Noble)
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi8/opentenbase_5.0-1ubuntu1.noble_all.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi8/opentenbase-server_5.0-1ubuntu1.noble_amd64.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi8/opentenbase-client_5.0-1ubuntu1.noble_amd64.deb
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0-multi8/opentenbase-contrib_5.0-1ubuntu1.noble_amd64.deb
sudo apt install ./*.deb
```

## 软件包说明

| 软件包 | 描述 |
|--------|------|
| `opentenbase` | 元软件包（依赖 server + client） |
| `opentenbase-server` | 服务端二进制文件（postgres, gtm, pg_ctl）+ 服务驱动 |
| `opentenbase-client` | 客户端工具（psql, pg_dump） |
| `opentenbase-contrib` | 扩展组件（pgbench, oid2name 等） |
| `libopentenbase-dev` | 开发头文件 + pg_config |
| `opentenbase-doc` | SGML 文档源 |

## 快速开始

### 初始化集群

```bash
# 初始化 GTM + Coordinator + Datanode
opentenbase-ctl init
```

### 启动集群

```bash
# 启动所有节点
opentenbase-ctl start
```

### 检查状态

```bash
# 查看集群状态
opentenbase-ctl status
```

### 连接数据库

```bash
# 通过 psql 连接
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres
```

### 停止集群

```bash
# 停止所有节点
opentenbase-ctl stop
```

## 架构说明

### 安装路径

- **主目录**：`/usr/lib/opentenbase/`（与系统 PostgreSQL 隔离）
- **配置目录**：`/etc/opentenbase/`
- **数据目录**：`/var/lib/opentenbase/`
- **日志目录**：`/var/log/opentenbase/`
- **管理脚本**：`/usr/bin/opentenbase-ctl`

### 端口规划

| 服务 | 端口 | 说明 |
|------|------|------|
| GTM | 6666 | 全局事务管理器 |
| Coordinator | 5432 | 协调节点（对外） |
| Datanode | 15432 | 数据节点 |
| Coordinator Pooler | 6667 | 连接池 |
| Datanode Pooler | 6668 | 连接池 |
| Coordinator Forward | 6669 | 转发端口 |
| Datanode Forward | 6670 | 转发端口 |

### 启动顺序

```
opentenbase-ctl start
    ├── 1. start_gtm()           # 启动 GTM
    ├── 2. start_coord()         # 启动 Coordinator
    ├── 3. register_nodes()      # 注册节点到 pgxc_node
    │   ├── CREATE GTM NODE ...
    │   ├── CREATE NODE coord1 ...
    │   ├── CREATE NODE dn001 ...
    │   ├── pgxc_pool_reload()
    │   └── EXECUTE DIRECT ON (dn001) 'CREATE GTM NODE ...'
    ├── 4. start_dn1()           # 启动 Datanode
    └── 5. register_nodes()      # 最终注册（确保传播完成）
```

## 从源码构建

### 安装构建依赖

```bash
apt install -y debhelper-compat bison flex perl gcc g++ make \
    libreadline-dev zlib1g-dev libssl-dev libpam0g-dev \
    libxml2-dev libldap2-dev libossp-uuid-dev uuid-dev \
    libcurl4-openssl-dev liblz4-dev libzstd-dev \
    libcli11-dev libpqxx-dev quilt libtool pkg-config
```

### 克隆源码

```bash
git clone https://github.com/OpenTenBase/OpenTenBase.git
cd OpenTenBase
```

### 复制打包文件

```bash
cp -r /path/to/debian/ ./
```

### 构建软件包

```bash
# 完整编译
fakeroot debian/rules binary

# 或者仅重新打包（不重新编译）
fakeroot debian/rules binary
```

## 已知限制

1. **许可证问题**：OpenTenBase 需要有效许可证才能执行写操作。开源版本为只读模式。
2. **单机部署**：当前配置仅支持单机多节点。跨机器部署需要修改 `opentenbase.conf`。
3. **无 systemd**：某些容器环境没有 systemd，使用 `opentenbase-ctl` 直接管理。
4. **Ubuntu 20.04 支持**：由于 GitHub Actions runner 不可用，暂未提供 Focal 软件包。

## 故障排查

### 常见问题

#### 1. 安装失败：依赖关系问题

```bash
# 更新软件包列表
sudo apt update

# 修复依赖关系
sudo apt install -f
```

#### 2. 无法连接到数据库

```bash
# 检查集群状态
opentenbase-ctl status

# 查看日志
tail -f /var/log/opentenbase/coord.log
```

#### 3. GTM 启动失败

```bash
# 检查 GTM 日志
tail -f /var/log/opentenbase/gtm.log

# 重新初始化集群
opentenbase-ctl stop
opentenbase-ctl init
opentenbase-ctl start
```

#### 4. 端口冲突

```bash
# 检查端口占用
sudo netstat -tlnp | grep -E '(5432|6666|15432)'

# 停止冲突的服务
sudo systemctl stop postgresql
```

## 贡献指南

欢迎贡献代码、报告问题或提出改进建议！

### 报告问题

1. 访问 [Issues](https://github.com/muzimu217/OpenTenBase-deb/issues)
2. 点击 "New Issue"
3. 描述问题详情，包括：
   - Ubuntu 版本
   - 错误信息
   - 复现步骤

### 提交代码

1. Fork 本仓库
2. 创建特性分支：`git checkout -b feature/your-feature`
3. 提交更改：`git commit -m 'Add your feature'`
4. 推送分支：`git push origin feature/your-feature`
5. 创建 Pull Request

## 许可证

与 OpenTenBase 相同（Apache 2.0）。

## 相关链接

- **GitHub 仓库**：https://github.com/muzimu217/OpenTenBase-deb
- **上游仓库**：https://github.com/OpenTenBase/OpenTenBase
- **OpenTenBase 文档**：https://github.com/OpenTenBase/OpenTenBase/wiki

---

**维护者**：muzimu217  
**最后更新**：2026-05-20

## 使用 Docker 从源码构建

### 前提条件

- Docker 已安装并运行
- Git

### 快速开始

```bash
# 克隆仓库
git clone https://github.com/muzimu217/OpenTenBase-deb.git
cd opentenbase-deb

# 测试构建 Ubuntu 20.04
./test-build.sh -d ubuntu -v 20.04

# 测试构建 Debian 12
./test-build.sh -d debian -v 12

# 测试所有支持的发行版
./test-build.sh --all
```

### 支持的构建环境

| 发行版 | 版本 | 代号 | Dockerfile |
|--------|------|------|------------|
| Ubuntu | 20.04 | focal | docker-ubuntu-20.04.Dockerfile |
| Ubuntu | 22.04 | jammy | ubuntu-22.04.Dockerfile |
| Ubuntu | 24.04 | noble | ubuntu-24.04.Dockerfile |
| Debian | 11 | bullseye | docker-debian-11.Dockerfile |
| Debian | 12 | bookworm | docker-debian-12.Dockerfile |

### 手动构建

```bash
# 构建 Ubuntu 20.04 的 Docker 镜像
docker build -f docker-ubuntu-20.04.Dockerfile -t opentenbase-builder:focal .

# 克隆 OpenTenBase 源码
git clone --depth=1 https://github.com/OpenTenBase/OpenTenBase.git source

# 运行构建
docker run \
    --rm \
    -v $(pwd)/source:/source \
    -v $(pwd)/output:/output \
    opentenbase-builder:focal

# 检查输出
ls -lh output/*.deb
```

### CI/CD 流水线

项目使用 GitHub Actions 进行自动化构建：

- **build.yml**: 原有工作流（Ubuntu 22.04/24.04）
- **build-multi.yml**: 多发行版工作流（Ubuntu 20.04/22.04/24.04 + Debian 11/12）
- **build-multi-optimized.yml**: 优化后的工作流（带缓存）

触发构建：

```bash
# 创建新版本标签
./release.sh v5.0-multi9

# 或手动创建
git tag -a v5.0-multi9 -m "Release v5.0-multi9"
git push origin v5.0-multi9
```

## 版本发布

### 使用发布脚本

```bash
# 显示帮助
./release.sh --help

# 模拟运行（不实际执行）
./release.sh --dry-run v5.0-multi9

# 带自定义消息的发布
./release.sh -m "Bug 修复和改进" v5.0-multi9

# 强制发布（跳过确认）
./release.sh --force v5.0-multi9
```

### 手动发布

1. 更新 `install.sh` 中的 TAG 版本
2. 提交更改
3. 创建 Git 标签
4. 推送标签到 GitHub
5. 等待 CI 构建并创建发布

```bash
# 更新 install.sh
sed -i 's/TAG=".*"/TAG="v5.0-multi9"/' install.sh

# 提交
git add install.sh
git commit -m "chore: update install.sh TAG to v5.0-multi9"

# 创建标签
git tag -a v5.0-multi9 -m "Release v5.0-multi9"

# 推送
git push origin main
git push origin v5.0-multi9
```

## 贡献指南

请参阅 [CONTRIBUTING_zh.md](CONTRIBUTING_zh.md)。

## 许可证

与 OpenTenBase 相同（Apache 2.0）。

---

**维护者**：muzimu217  
**最后更新**：2026-05-20
