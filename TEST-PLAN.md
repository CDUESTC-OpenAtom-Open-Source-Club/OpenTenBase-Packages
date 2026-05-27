# OpenTenBase 打包测试计划

## 测试目标
验证所有构建的 DEB/RPM 包在各发行版上能正确安装、多节点部署、基本 CRUD 操作通过，以及多版本安装和切换功能正常。

## 测试范围

### DEB 包（amd64）

| 发行版 | 安装测试 | 多节点测试 | 版本切换 | 状态 |
|--------|---------|-----------|---------|------|
| Ubuntu 20.04 (focal) | CI 通过 (run 26510778148) | 已编写脚本，待CI集成 | 已编写脚本，待CI集成 | CI 通过 |
| Ubuntu 22.04 (jammy) | CI 通过 (run 26510778148) | 已编写脚本，待CI集成 | 已编写脚本，待CI集成 | CI 通过 |
| Ubuntu 24.04 (noble) | CI 通过 (run 26510778148) | 已编写脚本，待CI集成 | 已编写脚本，待CI集成 | CI 通过 |
| Ubuntu 25.04 (plucky) | CI 通过 (run 26510778148) | 已编写脚本，待CI集成 | 已编写脚本，待CI集成 | CI 通过 |
| Debian 11 (bullseye) | CI 通过 (run 26510778148) | 已编写脚本，待CI集成 | 已编写脚本，待CI集成 | CI 通过 |
| Debian 12 (bookworm) | CI 通过 (run 26510778148) | 已编写脚本，待CI集成 | 已编写脚本，待CI集成 | CI 通过 |
| Debian 13 (trixie) | CI 通过 (run 26510778148) | 已编写脚本，待CI集成 | 已编写脚本，待CI集成 | CI 通过 |

### RPM 包（x86_64）

| 发行版 | 安装测试 | 多节点测试 | 版本切换 | 状态 |
|--------|---------|-----------|---------|------|
| Rocky Linux 8 | CI 通过 (run 26510778148) | 已编写脚本，待CI集成 | 已编写脚本，待CI集成 | CI 通过 |
| Rocky Linux 9 | CI 通过 (run 26510778148) | 已编写脚本，待CI集成 | 已编写脚本，待CI集成 | CI 通过 |
| CentOS Stream 8 | - | - | - | 未纳入CI（已弃用） |
| CentOS Stream 9 | CI 通过 (run 26510778148) | 已编写脚本，待CI集成 | 已编写脚本，待CI集成 | CI 通过 |
| AlmaLinux 8 | CI 通过 (run 26510778148) | 已编写脚本，待CI集成 | 已编写脚本，待CI集成 | CI 通过 |
| AlmaLinux 9 | CI 通过 (run 26510778148) | 已编写脚本，待CI集成 | 已编写脚本，待CI集成 | CI 通过 |
| openEuler 22.03 | CI 通过 (run 26510778148) | 已编写脚本，待CI集成 | 已编写脚本，待CI集成 | CI 通过 |
| Fedora 40 | CI 通过 (run 26510778148) | 已编写脚本，待CI集成 | 已编写脚本，待CI集成 | CI 通过 |

### RPM 包（aarch64）

| 发行版 | 安装测试 | 多节点测试 | 版本切换 | 状态 |
|--------|---------|-----------|---------|------|
| EulerOS 2.0 (aarch64) | 手动通过 | 手动通过 | 已编写脚本，待CI集成 | 部分完成 |

## 测试用例

### 1. 安装测试（每个发行版）
```bash
# DEB
sudo bash install.sh --version 5.0

# RPM
sudo bash install.sh --version 5.0
```

验证项：
- [ ] 包安装无报错
- [ ] 二进制文件存在：`postgres`, `psql`, `initdb`, `pg_ctl`, `gtm`, `opentenbase-ctl`
- [ ] 配置文件存在：`/etc/opentenbase/5.0/` 下模板文件
- [ ] 库文件存在：`libpq.so`, `libecpg.so` 等
- [ ] 用户 `opentenbase` 已创建
- [ ] `ldconfig` 后库可加载
- [ ] `/etc/opentenbase/current` 符号链接指向 `/etc/opentenbase/5.0`

### 2. 多版本安装测试
```bash
# 安装第一个版本
sudo bash install.sh --version 5.0

# 安装第二个版本
sudo bash install.sh --version 2.6.0
```

验证项：
- [ ] 两个版本可以并存安装（side-by-side）
- [ ] 版本 5.0 文件在 `/usr/lib/opentenbase/5.0/`
- [ ] 版本 2.6.0 文件在 `/usr/lib/opentenbase/2.6.0/`
- [ ] 配置目录独立：`/etc/opentenbase/5.0/` 和 `/etc/opentenbase/2.6.0/`
- [ ] 数据目录独立：`/var/lib/opentenbase/5.0/` 和 `/var/lib/opentenbase/2.6.0/`
- [ ] 日志目录独立：`/var/log/opentenbase/5.0/` 和 `/var/log/opentenbase/2.6.0/`
- [ ] 最后安装的版本为当前激活版本

### 3. 版本切换测试
```bash
# 查看已安装版本
opentenbase-switch-version

# 切换到 5.0
sudo opentenbase-switch-version 5.0

# 切换到 2.6.0
sudo opentenbase-switch-version 2.6.0
```

验证项：
- [ ] `opentenbase-switch-version` 列出所有已安装版本
- [ ] 当前激活版本标记正确
- [ ] 切换后 `/etc/opentenbase/current` 指向正确版本
- [ ] 切换后 `opentenbase-ctl` 使用对应版本的配置
- [ ] 切换后 `postgres --version` 显示正确版本
- [ ] 切换到不存在的版本时给出错误提示
- [ ] 切换时如果服务正在运行，提示用户确认

### 4. 版本切换后多节点测试
```bash
# 切换到目标版本
sudo opentenbase-switch-version 5.0

# 用 opentenbase-ctl 初始化和启动
sudo opentenbase-ctl init
sudo opentenbase-ctl start

# 验证集群
sudo opentenbase-ctl status
psql -h 127.0.0.1 -p 5432 -U opentenbase -c "SELECT version();"

# 停止
sudo opentenbase-ctl stop

# 切换到另一个版本
sudo opentenbase-switch-version 2.6.0
sudo opentenbase-ctl init
sudo opentenbase-ctl start
psql -h 127.0.0.1 -p 5432 -U opentenbase -c "SELECT version();"
sudo opentenbase-ctl stop
```

验证项：
- [ ] 每个版本的集群独立运行（不同数据目录）
- [ ] 切换版本后 init/start 使用正确版本的二进制
- [ ] `SELECT version()` 输出与当前激活版本一致
- [ ] 两个版本的端口配置互不冲突（或可配置不同端口）

### 5. 多节点部署测试（每个发行版至少跑一次）
```bash
# 使用 opentenbase-ctl 一键初始化
sudo opentenbase-ctl init
sudo opentenbase-ctl start
```

验证项：
- [ ] GTM 启动正常，端口 6666
- [ ] Datanode 启动正常
- [ ] Coordinator 启动正常，端口 5432
- [ ] `opentenbase-ctl status` 显示所有节点状态

### 6. CRUD 测试
```sql
-- 建表（分片表）
CREATE TABLE t1 (id int PRIMARY KEY, name text) DISTRIBUTE BY SHARD(id);

-- 插入
INSERT INTO t1 VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie');

-- 查询
SELECT * FROM t1;
SELECT * FROM t1 WHERE id = 2;

-- 更新
UPDATE t1 SET name = 'Alice2' WHERE id = 1;

-- 删除
DELETE FROM t1 WHERE id = 3;

-- 验证最终状态
SELECT * FROM t1 ORDER BY id;
-- 期望: 1|Alice2, 2|Bob

-- 建表（普通表）
CREATE TABLE t2 (id int, val text);
INSERT INTO t2 VALUES (100, 'test');
SELECT * FROM t2;

-- 清理
DROP TABLE t1;
DROP TABLE t2;
```

验证项：
- [ ] 分片表 CREATE 成功
- [ ] INSERT 3 条
- [ ] SELECT 全表和 WHERE 条件
- [ ] UPDATE 1 条
- [ ] DELETE 1 条
- [ ] 普通表 CRUD
- [ ] DROP TABLE 清理

### 7. 其他验证
- [ ] `opentenbase-ctl status` 输出正常
- [ ] `opentenbase-ctl stop` 干净停止
- [ ] 无 license 时仍可读写（license bypass 生效）
- [ ] 2 核服务器上 GTM 正常启动（已在 EulerOS ARM64 验证，2 核环境正常启动）

## 执行策略

### Docker 自动化测试（推荐）
为每个发行版创建 Docker 容器，运行安装 + 多节点 + CRUD + 版本切换测试脚本。

```bash
# 示例：Ubuntu 24.04
docker run --rm -v ./packages:/packages ubuntu:24.04 bash -c "
  apt-get update && apt-get install -y sudo procps libatomic1
  # 运行完整测试
  bash /test/full-test.sh
"
```

### 测试脚本
- `test/smoke-test.sh` — 单节点安装测试
- `test/multi-node-test.sh` — 多节点部署 + CRUD 测试
- `test/version-switch-test.sh` — 多版本安装 + 切换测试

## 优先级
1. **P0**：Ubuntu 22.04/24.04, Debian 12, Rocky 9 — 最常用服务器发行版
2. **P1**：Ubuntu 20.04, Debian 11, AlmaLinux 9, CentOS Stream 9
3. **P2**：其余发行版 + ARM64
