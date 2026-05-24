# OpenTenBase 多版本管理

English | [中文](VERSION-MANAGEMENT_zh.md)

## 概述

OpenTenBase 支持多个版本并行安装，类似于 PostgreSQL 管理 `postgresql-14`、`postgresql-15` 的方式。每个版本安装在独立的目录树中，拥有自己的配置和数据目录。

## 目录结构

```
/usr/lib/opentenbase/
├── 5.0/                    # v5.0 二进制文件和库（最新）
│   ├── bin/
│   ├── lib/
│   └── share/
├── 2.6.0/                  # v2.6.0 二进制文件和库
│   ├── bin/
│   ├── lib/
│   └── share/
└── 2.5.0/                  # v2.5.0 二进制文件和库
    ├── bin/
    ├── lib/
    └── share/

/etc/opentenbase/
├── 5.0/                    # v5.0 配置
│   ├── opentenbase.conf
│   ├── gtm.conf.template
│   └── ...
├── 2.6.0/                  # v2.6.0 配置
└── current -> 5.0/         # 当前活跃版本符号链接

/var/lib/opentenbase/
├── 5.0/                    # v5.0 数据
│   ├── gtm/
│   ├── coord/
│   └── dn1/
└── 2.6.0/                  # v2.6.0 数据

/var/log/opentenbase/
├── 5.0/                    # v5.0 日志
│   ├── gtm.log
│   ├── coord.log
│   └── dn1.log
└── 2.6.0/                  # v2.6.0 日志
```

## 快速开始

### 安装指定版本

```bash
# 安装 v5.0（默认，最新）
curl -sSL https://github.com/muzimu217/OpenTenBase-deb/releases/latest/download/install.sh | sudo bash

# 安装指定版本
curl -sSL https://github.com/muzimu217/OpenTenBase-deb/releases/latest/download/install.sh | sudo bash -s -- --version 5.0
curl -sSL https://github.com/muzimu217/OpenTenBase-deb/releases/latest/download/install.sh | sudo bash -s -- --version 2.6.0
```

### 列出已安装版本

```bash
opentenbase-switch-version
```

输出示例：
```
已安装的 OpenTenBase 版本：

  5.0 (活跃)
    安装路径: /usr/lib/opentenbase/5.0
    协调器端口: 5432

[INFO] 当前版本: 5.0
```

### 切换版本

```bash
# 切换到 v5.0（最新）
sudo opentenbase-switch-version 5.0

# 切换到 v2.6.0
sudo opentenbase-switch-version 2.6.0
```

### 验证当前版本

```bash
# 检查当前活跃版本
readlink /etc/opentenbase/current

# 检查二进制版本
/usr/lib/opentenbase/5.0/bin/postgres --version
```

## 同时运行多个版本

默认情况下，每个版本使用相同的端口（协调器 5432，GTM 6666，数据节点 15432）。要同时运行多个版本，需要使用不同的端口。

### 方法一：编辑配置

```bash
# 停止当前版本
opentenbase-ctl stop

# 编辑第二个版本的配置
sudo vi /etc/opentenbase/2.6.0/opentenbase.conf

# 更改端口：
#   GTM_PORT=6667
#   COORD_PORT=5433
#   DN1_PORT=15433
#   COORD_FORWARD_PORT=6671
#   DN1_FORWARD_PORT=6672
#   COORD_POOLER_PORT=6669
#   DN1_POOLER_PORT=6670

# 初始化并启动第二个版本
sudo opentenbase-switch-version 2.6.0
opentenbase-ctl init
opentenbase-ctl start

# 启动第一个版本（需要切换回去）
sudo opentenbase-switch-version 5.0
opentenbase-ctl start
```

### 方法二：环境变量覆盖

```bash
# 使用 OTB_CONFIG 指向特定版本配置
OTB_CONFIG=/etc/opentenbase/5.0/opentenbase.conf opentenbase-ctl start
OTB_CONFIG=/etc/opentenbase/2.6.0/opentenbase.conf opentenbase-ctl start
```

## 版本管理命令

| 命令 | 说明 |
|------|------|
| `opentenbase-switch-version` | 列出已安装版本 |
| `opentenbase-switch-version 5.0` | 切换到 v5.0 |
| `opentenbase-switch-version 2.6.0` | 切换到 v2.6.0 |
| `opentenbase-ctl init` | 初始化集群（当前版本） |
| `opentenbase-ctl start` | 启动集群（当前版本） |
| `opentenbase-ctl stop` | 停止集群（当前版本） |
| `opentenbase-ctl status` | 检查状态（当前版本） |

## 版本间升级

### 就地升级（同一大版本）

```bash
# 停止当前版本
opentenbase-ctl stop

# 安装新包（会覆盖版本目录中的文件）
sudo dpkg -i opentenbase_5.1-1ubuntu1_amd64.deb

# 使用更新的二进制文件启动
opentenbase-ctl start
```

### 并行升级（不同大版本）

```bash
# 在现有版本旁安装新版本
sudo bash install.sh --version 2.6.0

# 切换到新版本
sudo opentenbase-switch-version 2.6.0

# 初始化新版本数据
opentenbase-ctl init

# 启动新版本
opentenbase-ctl start

# 旧版本保留在 /var/lib/opentenbase/5.0/
```

## 故障排查

### "cannot read /etc/opentenbase/current/opentenbase.conf"

当前符号链接未设置。修复方法：

```bash
sudo ln -sf /etc/opentenbase/5.0 /etc/opentenbase/current
```

### 端口冲突

如果看到"端口已被占用"错误：

```bash
# 检查谁在使用该端口
ss -tlnp | grep 5432

# 停止冲突进程或更改配置中的端口
sudo vi /etc/opentenbase/<version>/opentenbase.conf
```

### 版本未找到

```bash
# 列出已安装版本
opentenbase-switch-version

# 检查配置目录是否存在
ls -la /etc/opentenbase/
```

## 包维护者指南

### 添加新版本

为新的 OpenTenBase 版本（如 v6.0）构建包时：

1. 更新 `debian/rules` 中的 `OTB_VERSION` 为 `6.0`
2. 更新 `debian/opentenbase-server.postinst` 中的 `OTB_VERSION` 为 `6.0`
3. 更新 `config/opentenbase.conf` 中的版本路径
4. 更新 `rpm/opentenbase.spec` 中的 `Version`
5. 如需并行运行，调整 `config/opentenbase.conf` 中的端口

### CI/CD 版本矩阵

构建工作流支持 `version` 参数：

```yaml
# 在 .github/workflows/build-deb.yml 中
workflow_dispatch:
  inputs:
    version:
      description: 'OpenTenBase 版本（如 5.0, 6.0）'
      required: true
      default: '5.0'
```
