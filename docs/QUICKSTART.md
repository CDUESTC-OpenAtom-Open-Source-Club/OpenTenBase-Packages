# OpenTenBase 快速开始

[English](#english) | 中文

> **5 分钟完成安装，1 条命令启动集群。**

---

## 系统要求

| 资源 | 最低 | 推荐 |
|------|------|------|
| 内存 | 3 GB | 4 GB+ |
| 磁盘 | 2 GB | 10 GB+ |
| CPU | 1 核 | 2+ 核 |
| 系统 | Ubuntu 20.04+ / Debian 11+ / RHEL 8+ / Fedora 40+ | Ubuntu 24.04 / Debian 12 |

> 内存 <3GB 的服务器集群可能因 OOM 无法启动。

---

## 方式一：APT 安装（Ubuntu / Debian）

```bash
# 1. 配置仓库
curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-apt.sh | sudo bash

# 2. 安装
sudo apt update && sudo apt install -y opentenbase

# 3. 初始化并启动集群
sudo opentenbase-ctl init
sudo opentenbase-ctl start

# 4. 验证
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1 -c "SELECT version();"
```

## 方式二：RPM 安装（RHEL / CentOS / Rocky / Alma / Fedora / openEuler）

```bash
# 1. 配置仓库
curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-rpm.sh | sudo bash

# 2. 安装
sudo dnf install -y opentenbase

# 3. 初始化并启动集群
sudo opentenbase-ctl init
sudo opentenbase-ctl start

# 4. 验证
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1 -c "SELECT version();"
```

## 方式三：Docker 部署

```bash
# 1. 拉取镜像
docker pull ghcr.io/muzimu217/opentenbase-runtime:v5.0-p6

# 2. 启动（单节点演示）
docker run -d --name opentenbase -p 5432:5432 \
  ghcr.io/muzimu217/opentenbase-runtime:v5.0-p6

# 3. 连接（容器内 psql 已在 PATH 中）
psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres
```

Docker Compose 完整集群（GTM + Coordinator + 2 Datanode）：

```bash
git clone https://github.com/muzimu217/OpenTenBase-deb.git
cd OpenTenBase-deb/docker/compose
docker compose up -d --build
```

---

## 连接数据库

安装后使用 `opentenbase-psql` 连接（不是系统自带的 `psql`）：

```bash
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1
```

## 集群管理

```bash
sudo opentenbase-ctl init      # 初始化集群
sudo opentenbase-ctl start     # 启动所有节点
sudo opentenbase-ctl status    # 查看状态
sudo opentenbase-ctl stop      # 停止集群
sudo opentenbase-ctl restart   # 重启集群
```

## 创建分布式表

```sql
-- 连接到 Coordinator
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1

-- 创建分片表
CREATE TABLE users (
    id int PRIMARY KEY,
    name text,
    email text
) DISTRIBUTE BY SHARD(id);

-- 插入数据
INSERT INTO users VALUES
    (1, 'Alice', 'alice@example.com'),
    (2, 'Bob', 'bob@example.com'),
    (3, 'Charlie', 'charlie@example.com');

-- 查询
SELECT * FROM users WHERE id = 2;
```

## 多版本管理

```bash
# 查看已安装版本
opentenbase-switch-version

# 切换版本
sudo opentenbase-switch-version 5.0
sudo opentenbase-switch-version 2.6.0
```

---

## 支持的系统

| 发行版 | DEB | RPM |
|--------|:---:|:---:|
| Ubuntu 20.04 / 22.04 / 24.04 / 25.04 | ✅ | — |
| Debian 11 / 12 / 13 | ✅ | — |
| Rocky Linux 8 / 9 | — | ✅ |
| AlmaLinux 8 / 9 | — | ✅ |
| CentOS Stream 8 / 9 | — | ✅ |
| Fedora 40 | — | ✅ |
| openEuler 22.03 | — | ✅ |

---

## 故障排查

**集群启动失败（OOM）**
```bash
# 检查内存
free -h
# 最低需要 3GB，推荐 4GB+
```

**端口被占用**
```bash
# 检查端口
ss -tlnp | grep -E '5432|6666|15432'
# 停止占用进程后重新初始化
```

**连接被拒绝**
```bash
# 检查集群状态
sudo opentenbase-ctl status
# 检查 pg_hba.conf
cat /var/lib/opentenbase/5.0/coord/pg_hba.conf
```

---

## 更多文档

| 文档 | 说明 |
|------|------|
| [README](README.md) | 项目概览、架构、完整特性列表 |
| [教程系列](tutorials/) | 从入门到高级的完整教程 |
| [源码构建](source-build-guide.md) | 从源码编译 OpenTenBase |
| [多版本管理](MULTI-VERSION-PLAN.md) | 多版本并存和切换 |
| [GPG 签名](GPG-SIGNING.md) | 包签名验证说明 |
| [测试报告](TEST-VERIFICATION-PLAN.md) | 完整测试验证计划和结果 |

---

<a id="english"></a>

## Quick Start (English)

### APT (Ubuntu / Debian)

```bash
curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-apt.sh | sudo bash
sudo apt update && sudo apt install -y opentenbase
sudo opentenbase-ctl init && sudo opentenbase-ctl start
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1 -c "SELECT version();"
```

### RPM (RHEL / CentOS / Rocky / Fedora)

```bash
curl -sSL https://raw.githubusercontent.com/muzimu217/OpenTenBase-deb/main/scripts/setup-rpm.sh | sudo bash
sudo dnf install -y opentenbase
sudo opentenbase-ctl init && sudo opentenbase-ctl start
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d template1 -c "SELECT version();"
```

### Docker

```bash
docker pull ghcr.io/muzimu217/opentenbase-runtime:v5.0-p6
docker run -d --name opentenbase -p 5432:5432 ghcr.io/muzimu217/opentenbase-runtime:v5.0-p6
```

---

**Last Updated**: 2026-06-01
