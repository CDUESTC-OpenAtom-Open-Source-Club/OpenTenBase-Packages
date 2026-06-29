# 基础操作

## 一、集群管理

### 1.1 启动集群

```bash
opentenbase_ctl start
```

**输出示例：**
```
starting gtm ...
starting coordinator ...
starting datanode ...
start complete
```

### 1.2 停止集群

```bash
opentenbase_ctl stop
```

**输出示例：**
```
stopping gtm ...
stopping coordinator ...
stopping datanode ...
stop complete
```

### 1.3 重启集群

```bash
opentenbase_ctl stop
opentenbase_ctl start
```

### 1.4 查看状态

```bash
opentenbase_ctl status
```

**输出示例：**
```
OpenTenBase Cluster Status
===========================
GTM:      Running  (PID: 12345)
Coordinator: Running  (PID: 12346)
Datanode: Running  (PID: 12347)
```

### 1.5 查看日志

```bash
# GTM 日志
tail -f /var/log/opentenbase/gtm.log

# Coordinator 日志
tail -f /var/log/opentenbase/coord.log

# Datanode 日志
tail -f /var/log/opentenbase/dn1.log
```

## 二、数据库连接

### 2.1 使用 psql 连接

```bash
# 连接 Coordinator（默认端口 5432）
psql -h 127.0.0.1 -p 5432 -U opentenbase postgres

# 连接 Datanode（端口 15432）
psql -h 127.0.0.1 -p 15432 -U opentenbase postgres
```

### 2.2 连接参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-h` | 主机地址 | 127.0.0.1 |
| `-p` | 端口号 | 5432 (Coordinator) |
| `-U` | 用户名 | opentenbase |
| `-d` | 数据库名 | postgres |

### 2.3 常用 psql 命令

```sql
-- 列出所有数据库
\l

-- 列出所有表
\dt

-- 查看表结构
\d table_name

-- 退出
\q

-- 执行 SQL 文件
\i /path/to/file.sql

-- 切换数据库
\c database_name

-- 显示当前查询
\g
```

## 三、SQL 基础操作

### 3.1 创建数据库

```sql
-- 创建数据库
CREATE DATABASE myapp;

-- 切换到新数据库
\c myapp
```

### 3.2 创建表

```sql
-- 创建用户表
CREATE TABLE users (
    id INT PRIMARY KEY,
    username TEXT NOT NULL,
    email TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 创建订单表（示例分片表）
CREATE TABLE orders (
    id INT PRIMARY KEY,
    user_id INT,
    amount DECIMAL(10,2),
    status TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
```

### 3.3 插入数据

```sql
-- 插入单条数据
INSERT INTO users (id, username, email) 
VALUES (1, 'alice', 'alice@example.com');

-- 插入多条数据
INSERT INTO users (id, username, email) 
VALUES 
    (2, 'bob', 'bob@example.com'),
    (3, 'charlie', 'charlie@example.com');

-- 从查询结果插入
INSERT INTO users (username, email)
SELECT username, email FROM external_users;
```

### 3.4 查询数据

```sql
-- 查询所有数据
SELECT * FROM users;

-- 条件查询
SELECT * FROM users WHERE username = 'alice';

-- 排序
SELECT * FROM users ORDER BY created_at DESC;

-- 分页
SELECT * FROM users ORDER BY id LIMIT 10 OFFSET 20;

-- 聚合查询
SELECT COUNT(*) FROM users;
SELECT MAX(id) FROM users;
SELECT AVG(amount) FROM orders;

-- 连接查询
SELECT u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;
```

### 3.5 更新数据

```sql
-- 更新单条记录
UPDATE users SET email = 'newemail@example.com' WHERE id = 1;

-- 批量更新
UPDATE users SET email = 'updated@example.com' WHERE id IN (1, 2, 3);
```

### 3.6 删除数据

```sql
-- 删除单条记录
DELETE FROM users WHERE id = 1;

-- 条件删除
DELETE FROM users WHERE created_at < '2026-01-01';

-- 清空表（保留表结构）
TRUNCATE TABLE users;

-- 删除表
DROP TABLE users;
```

## 四、节点管理

### 4.1 查看节点信息

```sql
-- 查看所有注册的节点
SELECT * FROM pgxc_node;
```

**输出示例：**
```
    node_name     | node_type | node_port | host | nodeis_primary | nodeis_preferred
------------------+-----------+-----------+------+----------------+-----------------
 gtm_master       | gtm       |      6666 | ::1  | t              | t
 coord1           | coordinator |      5432 | ::1  | f              | f
 dn001            | datanode  |     15432 | ::1  | t              | t
(3 rows)
```

### 4.2 节点类型说明

| node_type | 说明 | 典型端口 |
|-----------|------|----------|
| gtm | 全局事务管理器 | 6666 |
| coordinator | 协调节点 | 5432 |
| datanode | 数据节点 | 15432+ |

### 4.3 节点状态检查

```sql
-- 检查 Coordinator 是否能连接 GTM
SELECT pgxc_pool_reload();

-- 查看 Coordinator 的连接池状态
SELECT * FROM pgxc_pool_relation;
```

### 4.4 重载连接池

```sql
-- 当节点配置变更后，需要重载连接池
SELECT pgxc_pool_reload();
```

## 五、分布式查询

### 5.1 理解分布式查询

在 OpenTenBase 中，SQL 语句会被 Coordinator 解析后路由到对应的数据节点执行。

**示例场景：**
```
Client → Coordinator → [解析 SQL] → GTM (获取 GXID)
                          ↓
                    [路由到 DN]
                          ↓
                    DN001, DN002
                          ↓
                    [执行查询]
                          ↓
                    [聚合结果]
                          ↓
                    Coordinator
                          ↓
                    Client
```

### 5.2 分布式查询示例

```sql
-- 跨节点查询
SELECT COUNT(*) FROM users;

-- Coordinator 会将查询发送到所有 Datanode
-- 各 Datanode 返回计数
-- Coordinator 聚合结果

-- 分布式 JOIN
SELECT u.username, o.amount
FROM users u
JOIN orders o ON u.id = o.user_id;

-- Coordinator 会：
-- 1. 识别 JOIN 条件
-- 2. 确定 JOIN 策略（Hash Join / Nested Loop Join）
-- 3. 路由到对应的 Datanode
-- 4. 执行 JOIN 操作
-- 5. 返回结果
```

### 5.3 查看执行计划

```sql
-- 查看查询执行计划
EXPLAIN SELECT * FROM users;

-- 查看详细执行计划
EXPLAIN ANALYZE SELECT * FROM users;

-- 查看分布式执行计划
EXPLAIN VERBOSE SELECT * FROM users;
```

**输出示例：**
```
Remote SQL: SELECT id, username FROM public.users
```

## 六、性能监控

### 6.1 查看活动连接

```sql
-- 查看当前活动连接
SELECT * FROM pg_stat_activity;
```

### 6.2 查看表统计

```sql
-- 查看表的访问统计
SELECT * FROM pg_stat_user_tables;
```

### 6.3 查看索引统计

```sql
-- 查看索引使用情况
SELECT * FROM pg_stat_user_indexes;
```

### 6.4 查看慢查询

```sql
-- 查看执行时间超过 1 秒的查询
SELECT query, calls, total_time, mean_time 
FROM pg_stat_statements 
WHERE mean_time > 1000 
ORDER BY mean_time DESC;
```

## 七、数据备份与恢复

### 7.1 备份数据

```bash
# 备份 Coordinator
pg_dump -h 127.0.0.1 -p 5432 -U opentenbase myapp > myapp_backup.sql

# 备份 Datanode
pg_dump -h 127.0.0.1 -p 15432 -U opentenbase myapp > myapp_dn1_backup.sql
```

### 7.2 恢复数据

```bash
# 恢复到 Coordinator
psql -h 127.0.0.1 -p 5432 -U opentenbase myapp < myapp_backup.sql

# 恢复到 Datanode
psql -h 127.0.0.1 -p 15432 -U opentenbase myapp < myapp_dn1_backup.sql
```

## 八、常见错误排查

### 8.1 连接被拒绝

**错误信息：**
```
psql: error: could not connect to server: Connection refused
```

**排查步骤：**
```bash
# 1. 检查集群状态
opentenbase_ctl status

# 2. 检查端口监听
sudo netstat -tlnp | grep 5432

# 3. 检查防火墙
sudo ufw status

# 4. 查看日志
tail -f /var/log/opentenbase/coord.log
```

### 8.2 节点未注册

**错误信息：**
```
ERROR: can not get master gtm info from pgxc_node
```

**解决方法：**
```sql
-- 手动注册 GTM 节点
CREATE GTM NODE gtm_master WITH (HOST='127.0.0.1', PORT=6666, PRIMARY);

-- 手动注册 Coordinator
CREATE NODE coord1 WITH (TYPE='coordinator', HOST='127.0.0.1', PORT=5432, FORWARD=6669);

-- 手动注册 Datanode
CREATE NODE dn001 WITH (TYPE='datanode', HOST='127.0.0.1', PORT=15432, FORWARD=6670, PRIMARY, PREFERRED);

-- 重载连接池
SELECT pgxc_pool_reload();
```

### 8.3 查询超时

**错误信息：**
```
ERROR: canceling statement due to statement timeout
```

**解决方法：**
```sql
-- 增加超时时间
SET statement_timeout = '5min';

-- 或者优化查询
CREATE INDEX idx_username ON users(username);
```

## 九、最佳实践

### 9.1 连接管理

```bash
# 使用连接池
# 不要频繁创建和销毁连接
# 推荐使用 pgBouncer 或应用级连接池
```

### 9.2 查询优化

```sql
-- 使用 EXPLAIN 分析查询
EXPLAIN ANALYZE SELECT * FROM users WHERE username = 'alice';

-- 创建适当的索引
CREATE INDEX idx_username ON users(username);

-- 避免 SELECT *
SELECT id, username FROM users;  -- 只查询需要的字段
```

### 9.3 事务管理

```sql
-- 保持事务简短
BEGIN;
-- 执行快速操作
COMMIT;

-- 避免长时间运行的事务
BEGIN;
-- 不要在这里执行耗时操作
COMMIT;
```

### 9.4 监控与日志

```bash
# 定期检查日志
tail -f /var/log/opentenbase/*.log

# 监控磁盘空间
df -h /var/lib/opentenbase

# 监控连接数
SELECT count(*) FROM pg_stat_activity;
```

## 十、下一步

- 📖 阅读 [架构原理](03-architecture.md) - 深入理解分布式架构
- 🚀 了解 [高级功能](04-advanced.md) - 分片、高可用等
- 🧪 尝试 [实验2：分片策略](../labs/lab-02-sharding.md)

## 参考资源

- 🌐 [PostgreSQL 10 文档](https://www.postgresql.org/docs/10/)
- 📖 [OpenTenBase 官方文档](https://github.com/OpenTenBase/OpenTenBase)
- 💬 [问题反馈](https://github.com/CDUESTC-OpenAtom-Open-Source-Club/OpenTenBase-Packages/issues)