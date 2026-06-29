# 5分钟快速开始

## 环境要求

| 资源 | 最低 | 推荐 |
|------|------|------|
| 操作系统 | Ubuntu 20.04+ / Debian 11+ / RHEL 8+ / Fedora 40+ | Ubuntu 24.04 / Debian 12 |
| CPU | 1 核 | 2+ 核 |
| 内存 | 3 GB | 4 GB+ |
| 磁盘 | 2 GB | 10 GB+ |
| 权限 | sudo 权限 | root 或 sudo |

## 一键部署（白板机器推荐）

在干净的机器上，**一条命令**完成从安装到集群运行：

```bash
# 交互式（推荐，会问你几个问题）
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/deploy-opentenbase.sh | sudo bash

# 非交互式（全自动，默认单节点）
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/deploy-opentenbase.sh | sudo bash -s -- --yes

# 非交互式 + 自定义参数
sudo bash deploy-opentenbase.sh --yes \
    --cluster-name mycluster \
    --ssh-password mypass123 \
    --gtm-ip 192.168.1.10
```

脚本自动完成：安装包 → 创建用户 → 配置 sshpass → 路径符号链接 → 生成 INI → `opentenbase_ctl install` → 启动验证

---

## 手动安装（进阶）

### APT 安装（Ubuntu / Debian）

```bash
# 1. 配置 APT 仓库（自动检测系统版本）
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash

# 2. 安装
sudo apt update && sudo apt install -y opentenbase
```

### RPM 安装（RHEL / CentOS / Rocky / Alma / Fedora / openEuler）

```bash
# 1. 配置 YUM/DNF 仓库
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh | sudo bash

# 2. 安装
sudo dnf install -y opentenbase
```

### 配置并安装集群

```bash
# 复制配置文件模板
sudo cp /etc/opentenbase/5.0/opentenbase_config.ini.example /tmp/otb_config.ini

# 确保 sshpass 已安装（opentenbase_ctl 通过 sshpass 远程执行，无需配置互信）
sudo apt install -y sshpass   # 或 sudo dnf install -y sshpass

# 编辑配置文件中的 ssh-user / ssh-password 指定 SSH 账号
sudo vi /tmp/otb_config.ini

# 创建路径符号链接（修复 OSS_INSTALL_DIR 硬编码问题）
sudo mkdir -p /usr/local/install
sudo ln -sf /usr/lib/opentenbase/5.0 /usr/local/install/opentenbase

# 安装集群（GTM + CN + DN）
opentenbase_ctl install -c /tmp/otb_config.ini
```

**预期输出：**
```
>> install complete. Run: opentenbase_ctl start
```

### 启动集群

```bash
opentenbase_ctl start
```

**预期输出：**
```
starting gtm ...
starting coordinator ...
starting datanode ...
start complete
```

### 验证安装

```bash
# 查看集群状态
opentenbase_ctl status
```

**预期输出：**
```
OpenTenBase Cluster Status
===========================
GTM:      Running
Coordinator: Running
Datanode: Running
```

### 连接数据库

```bash
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase postgres
```

**预期输出：**
```
psql (10.0) (OpenTenBase 5.0.0)
Type "help" for help.

postgres=#
```

### 测试 SQL

```sql
-- 查看版本
SELECT version();

-- 查看节点
SELECT * FROM pgxc_node;

-- 创建测试表
CREATE TABLE test (id INT, name TEXT);

-- 插入数据
INSERT INTO test VALUES (1, 'Alice'), (2, 'Bob');

-- 查询数据
SELECT * FROM test;

-- 退出
\q
```

## 手动安装（进阶）

如果安装脚本不可用，可以从 [GitHub Releases](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases) 手动下载包：

```bash
# DEB 手动安装
# 从 releases 下载对应发行版的 .deb 包
sudo dpkg -i opentenbase_*.deb opentenbase-server_*.deb opentenbase-client_*.deb opentenbase-contrib_*.deb
sudo apt-get install -f -y  # 解决依赖问题

# RPM 手动安装
sudo dnf install ./opentenbase-*.rpm
```

## 常见问题

### 问题1：安装失败 - 找不到包

**错误信息：**
```
E: Unable to locate package opentenbase
```

**解决方法：**
```bash
# 确保已配置仓库
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash
sudo apt update
sudo apt install opentenbase
```

### 问题2：GTM 启动失败

**错误信息：**
```
FATAL: binding threads failed for 22
```

**解决方法：**
```bash
# 检查 CPU 核心数
nproc

# 检查内存（最低 3GB）
free -h

# 查看 GTM 日志
cat /var/log/opentenbase/5.0/gtm.log

# 重新安装
sudo opentenbase_ctl stop
sudo opentenbase_ctl delete
sudo opentenbase_ctl install -c /tmp/otb_config.ini
sudo opentenbase_ctl start
```

### 问题3：端口被占用

**错误信息：**
```
FATAL: could not bind IPv6 socket: Address already in use
```

**解决方法：**
```bash
# 检查端口占用
sudo ss -tlnp | grep -E '(5432|6666|15432)'

# 停止占用端口的服务
sudo kill -9 <PID>

# 重新安装
sudo opentenbase_ctl stop
sudo opentenbase_ctl delete
sudo opentenbase_ctl install -c /tmp/otb_config.ini
sudo opentenbase_ctl start
```

### 问题4：内存不足

**错误信息：**
```
ERROR: out of memory
```

**解决方法：**
```bash
# 检查内存（最低 3GB，推荐 4GB+）
free -h

# 如果内存不足，增加交换空间
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

## 架构概览

OpenTenBase 是一个分布式数据库，由三个核心组件组成：

```
┌─────────────────────────────────────────────────────────────┐
│                     OpenTenBase 集群                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│    ┌──────────┐                                              │
│    │   GTM    │ ← 全局事务管理器（Port: 6666）              │
│    └─────┬────┘                                              │
│          │                                                   │
│    ┌─────┴────┐                                              │
│    │          │                                              │
│ ┌──▼───┐  ┌──▼───┐         ┌────────┐                       │
│ │ CN1  │  │ CN2  │  ...    │  CNx   │ ← 协调节点（Port: 5432） │
│ └──┬───┘  └──┬───┘         └────────┘                       │
│    │        │                                                   │
│    └────┬───┘                                                   │
│         │                                                       │
│    ┌────┴────┐                                                  │
│    │         │                                                  │
│ ┌──▼───┐ ┌──▼───┐        ┌────────┐                          │
│ │ DN1  │ │ DN2  │  ...   │  DNx   │ ← 数据节点（Port: 15432） │
│ └──────┘ └──────┘        └────────┘                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**组件说明：**
- **GTM（Global Transaction Manager）**：管理全局事务，分配全局事务 ID（GXID）
- **Coordinator（协调节点）**：接收客户端请求，解析 SQL，路由到对应的数据节点
- **Datanode（数据节点）**：存储实际数据，执行 SQL 查询

## 下一步

- 📖 阅读 [基础操作](02-basic-ops.md) - 学习常用的数据库操作
- 🏗️ 了解 [架构原理](03-architecture.md) - 深入理解分布式架构
- 🚀 查看 [部署指南](07-deployment.md) - Docker 多节点、RPM 单节点/多机部署
- 📋 [快速开始总览](../QUICKSTART.md) - 所有安装方式汇总

## 资源链接

- 🌐 [GitHub 仓库](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages)
- 📦 [最新 Release](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases)
- 📖 [OpenTenBase 官方文档](https://github.com/OpenTenBase/OpenTenBase)
- 💬 [问题反馈](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/issues)