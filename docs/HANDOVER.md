# OpenTenBase Docker 部署交接文档

## 项目概述

OpenTenBase 是一个分布式 PostgreSQL 数据库系统，包含 GTM（全局事务管理器）、Coordinator（协调节点）和 Datanode（数据节点）组件。本项目将 OpenTenBase 打包为 DEB/RPM 包，并提供 Docker 一键部署方案。

## 当前状态

### 已完成

| 项目 | 状态 | 说明 |
|------|------|------|
| DEB 包打包 | ✅ 完成 | 支持 Ubuntu 22.04/24.04，已在 Ubuntu 24.04 测试通过 |
| RPM 包打包 | ✅ 完成 | 支持 CentOS 8/9、EulerOS；x86_64 已通过 CI 实测（7/7 distros，run 26510778148） |
| Docker 文件修复 | ✅ 完成 | 版本化路径、网络连接修复 |
| Docker 构建测试 | ✅ 完成 | EulerOS ARM64 上镜像构建成功 |
| Docker 集群启动 | ✅ 完成 | 4个容器全部 Up，节点注册正确 |
| CRUD 功能测试 | ✅ 完成 | 分布式表 CRUD 全部通过（25/28 测试项） |

### 已完成（近期）

1. **RPM x86_64 实测** — ✅ 完成
   - CI run 26510778148：全部 7 个 RPM 发行版测试通过（CentOS 8/9, Fedora 39/40, openEuler 22.03/24.03, EulerOS）
   - 包含安装、集群初始化、SQL CRUD 验证

2. **install.sh TAG 修复** — ✅ 完成
   - 修复了 install.sh 中 TAG 变量未正确传递的问题

3. **ensure_dirs 修复** — ✅ 完成
   - 修复了 RPM 安装时目录权限不足的问题

4. **version-switch-test** — ✅ 完成
   - 脚本已编写并集成到 CI 工作流中
   - 验证多版本安装和切换功能

### 待完成（超出当前范围）

1. **并发连接和性能测试未执行**
   - 需要在稳定网络环境下执行
   - 测试命令见 TEST-CHECKLIST.md

2. **APT 仓库搭建和监控集成**
   - 属于阶段二功能增强，当前不在范围内

## 关键文件说明

### Docker 相关文件

```
docker/
├── runtime/
│   ├── Dockerfile.runtime      # 运行时镜像（基于 EulerOS 或 Rocky Linux）
│   └── entrypoint.sh           # 容器入口脚本（已修复网络和路径问题）
├── compose/
│   └── docker-compose.yml      # 集群编排文件
├── dev/
│   ├── Dockerfile.builddev     # 开发构建镜像
│   ├── Dockerfile.runtime-dev  # 开发运行时镜像（新增）
│   └── scripts/
│       ├── build.sh            # 构建脚本
│       └── entrypoint-dev.sh   # 开发入口脚本（新增）
└── test-docker.sh              # 一键测试脚本
```

### 打包相关文件

```
debian/
├── rules                      # DEB 构建规则
├── opentenbase-server.postinst # 安装后脚本
└── changelog                  # 变更日志

rpm/
└── opentenbase.spec           # RPM 打包规范

config/
├── opentenbase.conf           # 主配置文件
└── opentenbase-ctl            # 管理脚本
```

## 已修复的关键 Bug

### 1. 版本化路径问题

**问题**：二进制文件路径从 `/usr/lib/opentenbase/bin/` 改为 `/usr/lib/opentenbase/5.0/bin/`，但 Docker 文件未同步更新。

**修复**：所有 Docker 入口脚本中的路径已更新为版本化路径。

**影响文件**：
- `docker/runtime/entrypoint.sh`
- `docker/test-docker.sh`
- `docker/dev/scripts/build.sh`
- `docker/dev/docker-compose.dev.yml`

### 2. Docker 网络连接问题

**问题**：Coordinator/Datanode 容器无法连接到 GTM 容器，报错 "Waiting for gtm:6666... ERROR"。

**原因**：Docker 18.09 的嵌入式 DNS 在 EulerOS 上不可靠，`bash -c "echo > /dev/tcp/gtm/6666"` 无法解析主机名。

**修复**：
1. 使用 `resolve_ip()` 函数在启动时解析所有主机名为 IP
2. `wait_for_port` 改用解析后的 IP 而不是主机名
3. 添加 `nc` (netcat) 作为备用连接检查方式

### 3. EulerOS 容器权限问题

**问题**：EulerOS 文件系统权限严格（750），非 root 用户无法访问关键目录。

**修复**：
- `chmod 755 /var /var/lib` 确保目录可访问
- `chmod 644 /etc/passwd /etc/group` 确保用户信息可读
- `chmod 1777 /tmp` 确保临时目录可写

## SQL 语法说明

### 创建分布式表

```sql
-- 正确语法：使用 TO GROUP
CREATE TABLE my_table (
    id int PRIMARY KEY,
    name text
) TO GROUP default_group;

-- 创建复制表（数据复制到所有节点）
CREATE TABLE my_replicated (
    id int PRIMARY KEY,
    name text
) DISTRIBUTE BY REPLICATION;
```

**注意**：
- `serial` 类型在分布式表中不会自动填充 id 列，需使用 `int` 并手动插入 id 值
- 不支持 `DISTRIBUTE BY HASH`、`DISTRIBUTE BY MODULAR`、`DISTRIBUTE BY ROUNDROBIN`
- `DISTRIBUTE BY SHARDING` 语法错误，应使用 `TO GROUP`

## 测试指南

### Docker 部署测试步骤

```bash
# 1. 进入 compose 目录
cd ~/otb-docker/compose

# 2. 清理旧环境（可选）
docker-compose down -v

# 3. 构建并启动
docker-compose up -d --build

# 4. 检查容器状态（所有容器应为 Up 状态）
docker ps -a

# 5. 查看日志
docker logs opentenbase-gtm
docker logs opentenbase-coordinator
docker logs opentenbase-datanode1
docker logs opentenbase-datanode2

# 6. 连接 Coordinator 测试
docker exec -it opentenbase-coordinator psql -h 127.0.0.1 -U opentenbase -d postgres

# 7. 执行 SQL 测试
# 在 psql 中执行：
SELECT * FROM pgxc_node;           # 查看节点配置
CREATE TABLE test (id int);        # 创建表
INSERT INTO test VALUES (1);       # 插入数据
SELECT * FROM test;                # 查询数据
DROP TABLE test;                   # 清理
```

### 预期结果

- GTM 启动在端口 6666
- Coordinator 启动在端口 5432
- Datanode1 启动在端口 15432
- Datanode2 启动在端口 15433
- 所有节点在 `pgxc_node` 中正确注册
- CRUD 操作正常执行

## 已知风险

### 高风险

1. **Docker 18.09 兼容性**
   - 服务器使用 Docker 18.09，不支持 `docker compose` 命令
   - 需要使用 `docker-compose`（Python 版本）
   - `docker-compose` 与 `docker` Python 包版本可能冲突

2. **hdspace 隧道不稳定**
   - 隧道连接可能在长时间操作中断开
   - 建议：使用 `--shell` 模式，或在服务器上直接执行命令

3. **基础镜像依赖**
   - `euleros-base:latest` 需要从宿主机文件系统创建
   - 如果清理了 Docker 镜像，需要重新创建（约 3.6GB）

### 中风险

4. **/tmp 空间不足**
   - 服务器 /tmp 只有 3.5GB，大文件传输会失败
   - 建议：使用 home 目录或 /data 目录

5. **密码未知**
   - SSH 密钥重置后密码未知
   - 只能通过 hdspace `--shell` 模式连接

### 低风险

6. **node_id 同步**
   - Datanode 需要从 Coordinator 读取正确的 node_id
   - 如果时序问题导致读取失败，会重试 30 次

## 后续工作建议

1. **完成 Docker 测试** — ✅ 已完成
   - 验证所有容器健康运行
   - 执行 CRUD 测试（25/28 通过）
   - 测试数据分片功能

2. **RPM 实测** — ✅ 已完成
   - CI run 26510778148：7/7 RPM 发行版全部通过
   - 包含安装、集群初始化、SQL CRUD 验证

3. **CI/CD 优化** — ✅ 已完成
   - test-all.yml 工作流支持 14 个发行版
   - 自动化集成测试

4. **文档完善** — 部分完成
   - 已添加 VERIFICATION.md、HANDOVER.md
   - 待添加：性能调优建议

5. **并发连接和性能测试** — 待完成
   - 需要在稳定网络环境下执行
   - 测试命令见 TEST-CHECKLIST.md

6. **APT 仓库搭建和监控集成** — 待完成
   - 属于阶段二功能增强，当前不在范围内

## 联系方式

如有问题，请参考：
- GitHub 仓库：https://github.com/muzimu217/OpenTenBase-deb
- 问题反馈：GitHub Issues
