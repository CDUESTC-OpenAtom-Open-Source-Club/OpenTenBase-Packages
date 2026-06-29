# OpenTenBase 部署指南

本文档覆盖 OpenTenBase 的所有部署方式：Docker 多节点、DEB 安装、RPM 安装。

## 部署模式总览

| 模式 | 组件 | 适用场景 | 安装方式 | 状态 |
|------|------|---------|---------|------|
| 单节点 | GTM + CN | 开发测试 | DEB / RPM | 已验证 |
| Docker 多节点 | GTM + CN + N*DN | 测试/生产 | Docker | 已验证 |
| 多机多节点 | GTM + CN + N*DN | 生产环境 | DEB / RPM | 已验证 |
| 单机多节点 | GTM + CN + DN | 不支持 | — | 端口冲突 |

### 为什么单机多节点不支持？

OpenTenBase 的 CN 和 DN 都有一个 **forward manager**（查询转发器），默认绑定到 `127.0.0.1:6670`。在单机部署时，CN 和 DN 共享同一个 IP，导致端口冲突：

```
CN forward manager: 127.0.0.1:6670  ← 第一个启动成功
DN forward manager: 127.0.0.1:6670  ← 第二个启动失败: "Address already in use"
```

Docker 多节点不受影响，因为每个容器有独立 IP（172.20.0.x），forward manager 可以各自绑定 6670 端口。

> **注意**：OpenTenBase 有两个独立的端口 — `pooler_port`（连接池，端口 6669）和 `forward_port`（查询转发，端口 6670）。不要混淆这两个端口。

---

## 方式一：Docker 多节点部署（推荐）

适用于：开发测试、功能验证、CI/CD 环境。

### 前提条件

- Docker 和 Docker Compose 已安装
- 至少 4GB 可用内存
- 至少 20GB 可用磁盘

### 部署架构

```
┌──────────────────────────────────────────────────────────────┐
│                    Docker Network (172.20.0.0/24)             │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ ┌────────┐│
│  │  GTM         │  │  CN          │  │  DN01    │ │ DN02   ││
│  │  172.20.0.2  │  │  172.20.0.3  │  │  .0.4    │ │ .0.5   ││
│  │  Port: 6666  │  │  Port: 5432  │  │  :15432  │ │ :15433 ││
│  │              │  │  Pool: 6669  │  │  Pool:6669│ │Pool:6669││
│  │              │  │  Fwd:  6670  │  │  Fwd:6670 │ │Fwd:6670││
│  └──────────────┘  └──────────────┘  └──────────┘ └────────┘│
│                                                              │
│  对外端口: CN 5432 → 宿主机 5432                              │
└──────────────────────────────────────────────────────────────┘
```

每个容器有独立 IP，`pooler_port`（6669）和 `forward_port`（6670）互不冲突。

### 快速部署

```bash
# 克隆仓库
git clone https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages.git
cd OpenTenBase-Packages/docker/compose

# 一键部署
DOCKER_BUILDKIT=0 docker-compose up -d
```

### 部署步骤详解

Docker Compose 自动完成以下步骤：

1. **构建镜像** — 基于 Rocky Linux 8，安装 OpenTenBase
2. **启动 4 个容器** — GTM, Coordinator, Datanode1, Datanode2
3. **初始化数据目录** — `initdb` 带 `--master_gtm_nodename/ip/port` 参数
4. **启动 GTM** → 启动 Coordinator → 启动 Datanodes
5. **配置端口** — 自动设置 `pooler_port=6669` 和 `forward_port=6670`
6. **注册节点** — 自动同步 pgxc_node 表，使用 IP 地址（解决 forward manager 主机名验证问题）
7. **创建节点组和 Shard Map** — `CREATE DEFAULT NODE GROUP` + `CREATE SHARDING GROUP`

### 连接数据库

```bash
# 从宿主机连接（CN 端口映射到宿主机 5432）
psql -h 127.0.0.1 -p 5432 -U opentenbase postgres

# 查看节点信息
SELECT node_name, node_type, node_host, node_port, node_forward_port FROM pgxc_node;

# 测试分布式建表
CREATE TABLE test (id int PRIMARY KEY, info text) DISTRIBUTE BY SHARD(id);
INSERT INTO test VALUES (1, 'hello'), (2, 'world');
SELECT * FROM test;
```

### 集群管理

```bash
# 停止集群
cd docker/compose && docker-compose down

# 启动集群
docker-compose up -d

# 查看日志
docker logs opentenbase-gtm
docker logs opentenbase-coordinator
docker logs opentenbase-datanode1

# 进入容器
docker exec -it opentenbase-coordinator bash
```

### 配置说明

**config.ini** — 集群配置文件：

```ini
[instance]
name=opentenbase_cluster       # 集群名称
type=distributed               # 部署类型
package=/data/opentenbase/opentenbase-5.0-aarch64.tar.gz

[gtm]
master=172.20.0.2              # GTM IP

[coordinators]
master=172.20.0.3              # CN IP（多个用逗号分隔）
nodes-per-server=1
conf=/data/opentenbase/postgres.conf

[datanodes]
master=172.20.0.4,172.20.0.5   # DN IP 列表
nodes-per-server=1
conf=/data/opentenbase/postgres.conf

[server]
ssh-user=opentenbase
ssh-password=opentenbase
ssh-port=22
```

**postgres.conf** — 节点额外配置：

```
listen_addresses = '*'
max_connections = 100
```

---

## 方式二：DEB 安装部署（Ubuntu / Debian）

适用于：Ubuntu 20.04/22.04/24.04、Debian 11/12 环境。

### 支持的系统

| 发行版 | 版本 | 代号 | 架构 |
|--------|------|------|------|
| Ubuntu | 20.04 | focal | amd64 |
| Ubuntu | 22.04 | jammy | amd64 |
| Ubuntu | 24.04 | noble | amd64 |
| Debian | 11 | bullseye | amd64 |
| Debian | 12 | bookworm | amd64 |

### 一键安装

```bash
curl -sLO https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/v5.0-multi10/install.sh
sudo bash install.sh
```

### 手动安装

```bash
# 下载（以 Ubuntu 24.04 为例）
wget https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/v5.0-multi10/opentenbase_5.0-1ubuntu1.noble_all.deb
wget https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/v5.0-multi10/opentenbase-server_5.0-1ubuntu1.noble_amd64.deb
wget https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/v5.0-multi10/opentenbase-client_5.0-1ubuntu1.noble_amd64.deb
wget https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/releases/download/v5.0-multi10/opentenbase-contrib_5.0-1ubuntu1.noble_amd64.deb

# 安装
sudo dpkg -i ./*.deb || sudo apt-get install -f -y
```

> **注意**：如果 `dpkg` 报告缺少依赖（如 `libossp-uuid16`），使用 `sudo dpkg --force-depends -i ./*.deb` 强制安装。

### 安装路径

| 路径 | 说明 |
|------|------|
| `/usr/lib/opentenbase/` | 主目录（与系统 PostgreSQL 隔离） |
| `/etc/opentenbase/` | 配置目录 |
| `/var/lib/opentenbase/` | 数据目录 |
| `/var/log/opentenbase/` | 日志目录 |
| `/usr/bin/opentenbase_ctl` | 集群管理二进制（符号链接 → 官方 C++ 实现） |
| `/usr/lib/opentenbase/5.0/bin/opentenbase_ctl` | 官方集群管理工具 |

### 准备 SSH 账号

`opentenbase_ctl` 通过 `sshpass` + SSH 账号密码在各节点间远程执行命令，**无需配置 SSH 密钥互信**：

```bash
# 1. 确保每台服务器都有 opentenbase 用户且密码一致
sudo passwd opentenbase

# 2. 在执行机上安装 sshpass
sudo apt install -y sshpass   # Debian/Ubuntu
sudo dnf install -y sshpass   # RHEL/Rocky/Alma

# 3. 在配置文件中填写 SSH 账号信息
# [server]
# ssh-user=opentenbase
# ssh-password=<your_password>
# ssh-port=22
```

> **提示**：如需 sudo 权限（如创建目录），请将 opentenbase 用户加入 wheel/sudo 组并启用 NOPASSWD。

### 创建路径符号链接

由于 `opentenbase_ctl` 内部硬编码了 `OSS_INSTALL_DIR=/usr/local/install/opentenbase`，需要创建符号链接：

```bash
sudo mkdir -p /usr/local/install
sudo ln -sf /usr/lib/opentenbase/5.0 /usr/local/install/opentenbase
```

### 集群管理

```bash
# 安装集群（GTM + CN + DN）
opentenbase_ctl install -c /tmp/otb_config.ini

# 启动所有节点
opentenbase_ctl start

# 查看集群状态
opentenbase_ctl status

# 停止所有节点
opentenbase_ctl stop

# 重启集群（stop + start）
opentenbase_ctl stop
opentenbase_ctl start
```

### 连接数据库

```bash
psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres
```

### 卸载

```bash
sudo apt-get remove opentenbase
```

---

## 方式三：RPM 单节点部署

适用于：EulerOS / CentOS / aarch64 环境，单节点开发测试。

### 前提条件

- EulerOS / CentOS / aarch64 系统
- rpmbuild 工具（`yum install rpm-build`）
- OpenTenBase 编译产物 tarball（`opentenbase-5.0-aarch64.tar.gz`）

### 安装步骤

```bash
# 1. 构建 RPM
bash build-rpm.sh /path/to/opentenbase-5.0-aarch64.tar.gz

# 2. 安装 RPM
sudo rpm -ivh ~/rpmbuild/RPMS/aarch64/opentenbase-5.0.0-1.aarch64.rpm

# 3. 验证安装
psql --version
initdb --version
gtm --version
```

### 单节点部署（GTM + CN）

```bash
# 设置环境变量
export LD_LIBRARY_PATH=/usr/lib/opentenbase/lib
export PATH=/usr/lib/opentenbase/bin:$PATH

# 创建数据目录
mkdir -p ~/otb-data/{gtm,cn}

# 1. 初始化 GTM
gtm_ctl init -Z gtm -D ~/otb-data/gtm

# 2. 启动 GTM
gtm -D ~/otb-data/gtm -l ~/otb-data/gtm.log &

# 3. 初始化 CN（必须指定 GTM 信息）
initdb -D ~/otb-data/cn --nodename=cn0001 --nodetype=coordinator \
  --master_gtm_nodename=gtm0001 --master_gtm_ip=127.0.0.1 --master_gtm_port=6666

# 4. 配置 CN
cat >> ~/otb-data/cn/postgresql.conf << 'EOF'
listen_addresses = '*'
port = 5432
EOF

cat >> ~/otb-data/cn/pg_hba.conf << 'EOF'
host all all 0.0.0.0/0 trust
EOF

# 5. 启动 CN
pg_ctl -D ~/otb-data/cn -l ~/otb-data/cn.log start -Z coordinator

# 6. 验证
psql -h 127.0.0.1 -p 5432 -U $(whoami) postgres -c "SELECT * FROM pgxc_node;"
```

### 卸载

```bash
sudo rpm -e opentenbase
```

### 安装路径说明

| 路径 | 说明 |
|------|------|
| `/usr/lib/opentenbase/bin/` | 主程序目录 |
| `/usr/lib/opentenbase/lib/` | 库文件 |
| `/usr/lib/opentenbase/share/` | 共享数据 |
| `/usr/lib/opentenbase/include/` | 头文件 |
| `/usr/bin/psql`, `/usr/bin/initdb` 等 | 符号链接 |
| `/etc/ld.so.conf.d/opentenbase.conf` | 库路径配置 |

---

## 方式四：RPM 多机多节点部署

适用于：生产环境，多台 EulerOS/CentOS 服务器。

### 架构

```
服务器 A (192.168.1.10)     服务器 B (192.168.1.11)     服务器 C (192.168.1.12)
┌─────────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│  GTM (Port: 6666)   │    │  CN  (Port: 5432)   │    │  DN  (Port: 5432)   │
│  Fwd: 6669          │    │  Fwd: 6669          │    │  Fwd: 6669          │
└─────────────────────┘    └─────────────────────┘    └─────────────────────┘
```

每台服务器有独立 IP，forward manager 端口 6669 互不冲突。

### 前提条件

- 每台服务器都安装了 RPM 包
- 执行机已安装 `sshpass`，配置文件中 SSH 账号密码正确
- 防火墙开放必要端口

### 端口规划

| 服务 | 端口 | 说明 |
|------|------|------|
| GTM | 6666 | 全局事务管理器 |
| CN | 5432 | 协调节点（对外） |
| DN | 5432 | 数据节点 |
| Forward | 6669 | 连接池转发（各节点独立 IP，无冲突） |

### 部署步骤

#### 1. 在所有服务器安装 RPM

```bash
# 在每台服务器上执行
sudo rpm -ivh opentenbase-5.0.0-1.aarch64.rpm
```

#### 2. 初始化并启动 GTM（服务器 A）

```bash
# 服务器 A
export LD_LIBRARY_PATH=/usr/lib/opentenbase/lib
export PATH=/usr/lib/opentenbase/bin:$PATH

mkdir -p ~/otb-data/gtm
gtm_ctl init -Z gtm -D ~/otb-data/gtm
gtm -D ~/otb-data/gtm -l ~/otb-data/gtm.log &
```

#### 3. 初始化并启动 CN（服务器 B）

```bash
# 服务器 B
export LD_LIBRARY_PATH=/usr/lib/opentenbase/lib
export PATH=/usr/lib/opentenbase/bin:$PATH

mkdir -p ~/otb-data/cn
initdb -D ~/otb-data/cn --nodename=cn0001 --nodetype=coordinator \
  --master_gtm_nodename=gtm0001 --master_gtm_ip=192.168.1.10 --master_gtm_port=6666

cat >> ~/otb-data/cn/postgresql.conf << 'EOF'
listen_addresses = '*'
port = 5432
EOF

cat >> ~/otb-data/cn/pg_hba.conf << 'EOF'
host all all 0.0.0.0/0 trust
EOF

pg_ctl -D ~/otb-data/cn -l ~/otb-data/cn.log start -Z coordinator
```

#### 4. 初始化并启动 DN（服务器 C）

```bash
# 服务器 C
export LD_LIBRARY_PATH=/usr/lib/opentenbase/lib
export PATH=/usr/lib/opentenbase/bin:$PATH

mkdir -p ~/otb-data/dn
initdb -D ~/otb-data/dn --nodename=dn0001 --nodetype=datanode \
  --master_gtm_nodename=gtm0001 --master_gtm_ip=192.168.1.10 --master_gtm_port=6666

cat >> ~/otb-data/dn/postgresql.conf << 'EOF'
listen_addresses = '*'
port = 5432
EOF

cat >> ~/otb-data/dn/pg_hba.conf << 'EOF'
host all all 0.0.0.0/0 trust
EOF

pg_ctl -D ~/otb-data/dn -l ~/otb-data/dn.log start -Z datanode
```

#### 5. 配置 CN forward port（服务器 B）

```bash
# 服务器 B
psql -h 127.0.0.1 -p 5432 -U $(whoami) postgres \
  -c "UPDATE pgxc_node SET node_forward_port = 6669;"
```

#### 6. 在 DN 上注册所有节点（服务器 C）

```bash
# 服务器 C — DN 的 pgxc_node 是只读的，需要用 DROP/CREATE NODE
psql -h 127.0.0.1 -p 5432 -U $(whoami) postgres << 'EOSQL'
DROP NODE cn0001;
CREATE NODE cn0001 WITH (TYPE='coordinator', HOST='192.168.1.11', PORT=5432, FORWARD=6669);
EOSQL
```

#### 7. 在 CN 上注册 DN 节点并创建节点组（服务器 B）

```bash
# 服务器 B
psql -h 127.0.0.1 -p 5432 -U $(whoami) postgres << 'EOSQL'
CREATE NODE dn0001 WITH (TYPE='datanode', HOST='192.168.1.12', PORT=5432, FORWARD=6669);
CREATE DEFAULT NODE GROUP default_group WITH (dn0001);
CREATE SHARDING GROUP TO GROUP default_group;
CLEAN SHARDING;
EOSQL
```

#### 8. 验证

```bash
# 在 CN 上验证（服务器 B）
psql -h 127.0.0.1 -p 5432 -U $(whoami) postgres

-- 查看节点
SELECT node_name, node_type, node_host, node_port, node_forward_port FROM pgxc_node;

-- 测试分布式建表
CREATE TABLE test (id int PRIMARY KEY, info text) DISTRIBUTE BY SHARD(id);
INSERT INTO test VALUES (1, 'hello'), (2, 'world');
SELECT * FROM test;
DROP TABLE test;
```

---

## 常见问题

### 1. DN 启动失败："forward manager could not create listen socket"

**原因**：单机部署时 CN 和 DN 的 forward manager 都尝试绑定 127.0.0.1:6670。

**解决**：使用 Docker 部署（每个容器独立 IP）或多机部署（每台服务器独立 IP）。

### 2. "database system is in recovery mode"

**原因**：DN 启动失败后进入恢复模式。

**解决**：检查 DN 日志，通常是 forward manager 端口冲突导致。先停止所有节点，清理数据目录，使用正确的方式重新部署。

### 3. initdb 报错 "master_gtm_nodename not specified"

**原因**：OpenTenBase 的 `initdb` 需要 `--master_gtm_nodename`、`--master_gtm_ip`、`--master_gtm_port` 三个参数来在 pgxc_node 表中注册 GTM 信息。

**解决**：
```bash
initdb -D /path/to/data --nodename=node01 --nodetype=coordinator \
  --master_gtm_nodename=gtm0001 --master_gtm_ip=127.0.0.1 --master_gtm_port=6666
```

### 4. CN 无法连接 DN

**原因**：DN 的 pgxc_node 中没有正确的节点信息，或 forward port 未设置。

**解决**：在 DN 上用 `DROP NODE + CREATE NODE ... FORWARD=6669` 重新注册节点。

### 5. RPM 安装后找不到命令

**原因**：库路径未加载。

**解决**：
```bash
# 运行 ldconfig 更新库缓存
sudo ldconfig

# 或手动设置环境变量
export LD_LIBRARY_PATH=/usr/lib/opentenbase/lib
export PATH=/usr/lib/opentenbase/bin:$PATH
```

---

## 端口参考

| 服务 | 默认端口 | 说明 |
|------|---------|------|
| GTM | 6666 | 全局事务管理器 |
| CN | 5432 | 协调节点（客户端连接） |
| DN | 15432/15433 | 数据节点 |
| Pooler | 6669 | 连接池（CN/DN 各自绑定，需不同 IP） |
| Forward Manager | 6670 | 查询转发器（CN/DN 各自绑定，需不同 IP） |
