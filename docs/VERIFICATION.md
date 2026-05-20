# OpenTenBase .deb 安装验证报告

**日期：** 2026-05-18
**验证人：** muzimu217
**Release 版本：** v5.0

---

## 一、验证环境

### 测试服务器 1

| 项目 | 配置 |
|------|------|
| 平台 | 腾讯 CloudStudio |
| OS | Ubuntu 24.04.2 LTS (Noble Numbat) |
| CPU | 32 核 |
| 内存 | 4GB |
| 磁盘 | 16GB |
| 用户 | root |

### 测试服务器 2

| 项目 | 配置 |
|------|------|
| 平台 | 腾讯 CloudStudio |
| OS | Ubuntu 24.04.2 LTS (Noble Numbat) |
| CPU | 多核 |
| 内存 | 8GB |
| 磁盘 | 20GB |
| 用户 | root |

---

## 二、验证步骤与结果

### 步骤 1：下载安装包

```bash
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0/opentenbase-5.0-ubuntu24.04-amd64.tar.gz
tar xzf opentenbase-5.0-ubuntu24.04-amd64.tar.gz
```

**结果：** 6 个 .deb 文件成功解压

```
libopentenbase-dev_5.0-1ubuntu1_amd64.deb   (1.5 MB)
opentenbase_5.0-1ubuntu1_all.deb            (2.2 KB)
opentenbase-client_5.0-1ubuntu1_amd64.deb   (737 KB)
opentenbase-contrib_5.0-1ubuntu1_amd64.deb  (1.4 MB)
opentenbase-doc_5.0-1ubuntu1_all.deb        (2.6 MB)
opentenbase-server_5.0-1ubuntu1_amd64.deb   (6.2 MB)
```

### 步骤 2：安装

```bash
apt update
apt install -y ./*.deb
```

**结果：** 6 个包全部安装成功，依赖自动解决（libossp-uuid16, libpqxx-7.8t64）

### 步骤 3：初始化集群

```bash
opentenbase-ctl init
```

**结果：** 成功初始化 GTM、Coordinator、Datanode

### 步骤 4：启动集群

```bash
opentenbase-ctl start
```

**结果：** 三节点全部启动成功，自动配置 node group 和 sharding map

```
  starting gtm
server starting
  starting coord
  registering GTM node in pgxc_node ...
  registering coordinator node ...
  registering datanode node ...
  reloading connection pool ...
  starting dn1
  registering GTM node in pgxc_node ...
  registering coordinator node ...
  registering datanode node ...
  reloading connection pool ...
  propagating nodes to datanode ...
  setting up default node group ...
  creating sharding map ...
  node group setup complete
>> start complete
```

### 步骤 5：验证状态

```bash
opentenbase-ctl status
```

**结果：**

```
gtm:   RUNNING
dn1:   RUNNING
coord: RUNNING
```

### 步骤 6：验证数据库连接

```bash
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres
```

**结果：** 连接成功，查询正常

```
PostgreSQL 10.0 @ OpenTenBase_v5.0 OpenTenBase V5.21 2026-05-18 16:41:36

 node_name  | node_type | node_port | node_host
------------+-----------+-----------+-----------
 gtm_master | G         |      6666 | 127.0.0.1
 coord1     | C         |      5432 | 127.0.0.1
 dn001      | D         |     15432 | 127.0.0.1
```

### 步骤 7：验证 CRUD 操作

```sql
-- 创建表（使用 SHARD 分布）
CREATE TABLE t1(id int, name text) DISTRIBUTE BY SHARD(id);

-- 插入数据
INSERT INTO t1 VALUES (1, 'alice'), (2, 'bob'), (3, 'charlie');

-- 查询
SELECT * FROM t1 ORDER BY id;
 id |  name
----+---------
  1 | alice
  2 | bob
  3 | charlie
(3 rows)

-- 更新
UPDATE t1 SET name = 'alex' WHERE id = 1;

-- 删除
DELETE FROM t1 WHERE id = 3;

-- 验证
SELECT * FROM t1 ORDER BY id;
 id | name
----+------
  1 | alex
  2 | bob
(2 rows)

-- 清理
DROP TABLE t1;
```

**结果：** 全部 CRUD 操作通过

---

## 三、验证结论

| 检查项 | 状态 |
|--------|------|
| .deb 包下载 | 通过 |
| 依赖自动解决 | 通过 |
| 安装成功 | 通过 |
| 集群初始化 | 通过 |
| 集群启动 | 通过 |
| GTM 注册 | 通过 |
| Coordinator 连接 | 通过 |
| Datanode 查询 | 通过 |
| Node Group 自动配置 | 通过 |
| Sharding Map 自动创建 | 通过 |
| CREATE TABLE (DISTRIBUTE BY SHARD) | 通过 |
| INSERT | 通过 |
| SELECT | 通过 |
| UPDATE | 通过 |
| DELETE | 通过 |
| DROP TABLE | 通过 |

**结论：** OpenTenBase v5.0 .deb 安装包在 Ubuntu 24.04 上可正常安装和运行，支持完整的 CRUD 操作，已验证通过。

---

## 四、已知限制

1. **单机部署：** 当前配置仅支持单机多节点，跨机器部署需要修改配置
2. **系统要求：** 需要先执行 `apt update` 确保依赖库可用

---

## 五、安装命令汇总

```bash
# 完整安装流程
wget https://github.com/muzimu217/OpenTenBase-deb/releases/download/v5.0/opentenbase-5.0-ubuntu24.04-amd64.tar.gz
tar xzf opentenbase-5.0-ubuntu24.04-amd64.tar.gz
apt update
apt install -y ./*.deb
opentenbase-ctl init
opentenbase-ctl start
opentenbase-ctl status

# 测试 CRUD
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres -c "CREATE TABLE t1(id int, name text) DISTRIBUTE BY SHARD(id);"
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres -c "INSERT INTO t1 VALUES (1, 'hello');"
opentenbase-psql -h 127.0.0.1 -p 5432 -U opentenbase -d postgres -c "SELECT * FROM t1;"
```

---

**验证完成日期：** 2026-05-18
