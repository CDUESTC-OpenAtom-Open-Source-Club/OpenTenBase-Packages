# OpenTenBase 快速开始

[English](#english) | 中文

> **白板机器，一条命令，集群就跑起来了。**

---

## ⚠️ 重要提示：必须使用 opentenbase 用户

OpenTenBase 集群管理工具（opentenbase_ctl / pgxc_ctl）**必须使用 `opentenbase` 用户**进行 SSH 连接和部署操作。

**关键点：**
- opentenbase 用户必须存在（脚本会自动创建）
- opentenbase 用户的 home 目录是 `/var/lib/opentenbase`（系统用户，不在 `/home/`）
- SSH 密钥必须放在 `/var/lib/opentenbase/.ssh/`
- 不要尝试使用其他用户（如 root、developer）运行集群部署

**脚本会自动处理：**
1. 创建 opentenbase 系统用户
2. 配置 `/var/lib/opentenbase/.ssh/` 目录和密钥
3. 配置 authorized_keys 实现免密登录

---

## 🚀 一键部署（最快方式）

```bash
# 交互式（推荐）
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/deploy-opentenbase.sh | sudo bash

# 非交互式（全自动）
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/deploy-opentenbase.sh | sudo bash -s -- --yes
```

自动完成全部步骤：安装包 → 创建用户 → sshpass → 符号链接 → 生成配置 → `opentenbase_ctl install` → 启动验证

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

## 方式一：APT 安装 + 官方 opentenbase_ctl 部署（Ubuntu / Debian）

```bash
# 1. 配置仓库并安装
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash
sudo apt update && sudo apt install -y opentenbase

# 2. 安装 sshpass（opentenbase_ctl 通过 sshpass 远程执行，无需配置互信）
sudo apt install -y sshpass

# 3. 创建部署包 tar.gz（opentenbase_ctl 要求文件格式，不能是目录）
cd /tmp && mkdir otb-pkg && cp -af /usr/lib/opentenbase/5.0/* otb-pkg/
cd otb-pkg && tar -zcf /tmp/opentenbase-5.0.tar.gz * && cd / && rm -rf /tmp/otb-pkg

# 4. 创建配置并安装集群
sudo cp /etc/opentenbase/5.0/opentenbase_config.ini.example /tmp/otb_config.ini
# 编辑 [server] 部分：填写 ssh-user / ssh-password
sudo -u opentenbase opentenbase_ctl install -c /tmp/otb_config.ini

# 5. 验证
opentenbase_ctl start
opentenbase_ctl status
opentenbase-psql -h 127.0.0.1 -p 11003 -U opentenbase -d postgres -c "SELECT version();"
```

## 方式二：RPM 安装 + 官方 opentenbase_ctl 部署（RHEL / CentOS / Rocky / Alma / Fedora / openEuler）

```bash
# 1. 配置仓库并安装
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh | sudo bash
sudo dnf install -y opentenbase

# 2. 安装 sshpass（opentenbase_ctl 通过 sshpass 远程执行，无需配置互信）
sudo dnf install -y sshpass

# 3. 创建部署包 tar.gz（opentenbase_ctl 要求文件格式，不能是目录）
cd /tmp && mkdir otb-pkg && cp -af /usr/lib/opentenbase/5.0/* otb-pkg/
cd otb-pkg && tar -zcf /tmp/opentenbase-5.0.tar.gz * && cd / && rm -rf /tmp/otb-pkg

# 4. 创建配置并安装集群
sudo cp /etc/opentenbase/5.0/opentenbase_config.ini.example /tmp/otb_config.ini
# 编辑 [server] 部分：填写 ssh-user / ssh-password
sudo -u opentenbase opentenbase_ctl install -c /tmp/otb_config.ini

# 5. 验证
opentenbase_ctl start
opentenbase_ctl status
opentenbase-psql -h 127.0.0.1 -p 11003 -U opentenbase -d postgres -c "SELECT version();"
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
git clone https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages.git
cd OpenTenBase-Packages/docker/compose
docker compose up -d --build
```

---

## 连接数据库

安装后使用 `opentenbase-psql` 连接（不是系统自带的 `psql`）。**裸机（`opentenbase_ctl`）CN 端口 11003；Docker 映射 5432**：

```bash
opentenbase-psql -h 127.0.0.1 -p 11003 -U opentenbase -d postgres
```

## 集群管理

使用官方 `opentenbase_ctl` 二进制管理集群（`install`/`delete`/`expand`/`shrink` 需要 `-c`；`start`/`stop`/`status` 不需要）：

```bash
opentenbase_ctl install -c /tmp/otb_config.ini   # 安装集群（initdb+配置+启动+注册）
opentenbase_ctl start     # 启动集群
opentenbase_ctl status    # 查看状态
opentenbase_ctl stop      # 停止集群
opentenbase_ctl delete -c /tmp/otb_config.ini    # 删除集群
opentenbase_ctl expand -c /tmp/otb_config.ini    # 扩容
opentenbase_ctl shrink -c /tmp/otb_config.ini    # 缩容
```

## 创建分布式表

```sql
-- 连接到 Coordinator（裸机端口 11003）
opentenbase-psql -h 127.0.0.1 -p 11003 -U opentenbase -d postgres

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

> **安装其他版本**：APT/RPM 仓库通过 component 区分版本。安装非默认版本：
> ```bash
> # APT: 指定版本安装
> curl -sSL .../setup-apt.sh | sudo bash -s -- --version 2.6.0
> sudo apt install opentenbase
>
> # 或手动修改 sources.list 中的 component（main → v260）
> ```

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
ss -tlnp | grep -E '11003|6666|15432'
# 停止占用进程后重新初始化
```

**连接被拒绝**
```bash
# 检查集群状态
opentenbase_ctl status
# 检查 pg_hba.conf
cat /var/lib/opentenbase/5.0/coord/pg_hba.conf
```

**推荐 sysctl 参数**（3-4GB 内存环境）
```bash
# /etc/sysctl.d/99-opentenbase.conf
kernel.shmmax = 1717986918
vm.overcommit_memory = 2
vm.overcommit_ratio = 90
```

---

## 生产注意事项

| 项目 | 说明 |
|------|------|
| **GTM 单点** | GTM 是全局事务管理器，无内置高可用。生产环境建议监控 GTM 进程 |
| **备份恢复** | 使用 `pg_dump` / `pg_dumpall` 进行逻辑备份，暂无内置物理备份工具 |
| **启动顺序** | `opentenbase_ctl start` 按 GTM → Coordinator → Datanode 顺序启动 |
| **安装脚本安全** | `setup-apt.sh` / `setup-rpm.sh` 通过 HTTPS 传输，包使用 GPG 签名验证 |

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
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-apt.sh | sudo bash
sudo apt update && sudo apt install -y opentenbase
# Configure SSH and install cluster (see Chinese section above for full steps)
sudo cp /etc/opentenbase/5.0/opentenbase_config.ini.example /tmp/otb_config.ini
sudo -u opentenbase opentenbase_ctl install -c /tmp/otb_config.ini
opentenbase-psql -h 127.0.0.1 -p 11003 -U opentenbase -d postgres -c "SELECT version();"
```

### RPM (RHEL / CentOS / Rocky / Fedora)

```bash
curl -sSL https://raw.githubusercontent.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/main/scripts/setup-rpm.sh | sudo bash
sudo dnf install -y opentenbase
# Configure SSH and install cluster (see Chinese section above for full steps)
sudo cp /etc/opentenbase/5.0/opentenbase_config.ini.example /tmp/otb_config.ini
sudo -u opentenbase opentenbase_ctl install -c /tmp/otb_config.ini
opentenbase-psql -h 127.0.0.1 -p 11003 -U opentenbase -d postgres -c "SELECT version();"
```

### Docker

```bash
docker pull ghcr.io/muzimu217/opentenbase-runtime:v5.0-p6
docker run -d --name opentenbase -p 5432:5432 ghcr.io/muzimu217/opentenbase-runtime:v5.0-p6
```

---

**Last Updated**: 2026-06-28
