# OpenTenBase 最佳实践

> 本文档总结了使用 OpenTenBase 的最佳实践，帮助您构建高性能、高可用的分布式数据库系统。

---

## 1. 架构设计

### 1.1 硬件规划

#### 1.1.1 CPU 配置

**推荐配置：**

| 角色 | CPU 核心数 | 说明 |
|------|-----------|------|
| GTM | 4-8 核 | 事务协调，不要求高性能 |
| Coordinator | 8-16 核 | SQL 解析和优化，需要较好性能 |
| Datanode | 16-32 核 | 数据处理和存储，核心组件 |

**注意事项：**
- GTM 线程数不能超过 CPU 核心数，避免 `binding threads failed` 错误
- 在 ≤2 核的机器上，GTM 的 `bind_service_threads()` 会生成空 cpuset 导致 `pthread_setaffinity_np` 返回 EINVAL
- `opentenbase-ctl` 会自动检测并编译 CPU-affinity shim（`noaffinity.so`）来绕过此问题
- 使用 `nproc` 检查核心数

```bash
# 检测 CPU 核心数
CPU_CORES=$(nproc 2>/dev/null || echo "2")
GTM_THREADS=$((CPU_CORES < 4 ? CPU_CORES : 4))
```

#### 1.1.2 内存配置

**推荐配置：**

| 角色 | 内存 | 说明 |
|------|------|------|
| GTM | 4-8 GB | 缓存事务信息 |
| Coordinator | 16-32 GB | 复杂查询优化 |
| Datanode | 32-64 GB | 数据缓存和排序 |

**内存参数优化：**

```ini
# postgresql.conf
shared_buffers = 内存的 25%   # Datanode 示例：16GB 内存设为 4GB
effective_cache_size = 内存的 50-75%
work_mem = 64MB  # 每个排序/哈希操作的工作内存
maintenance_work_mem = 256MB  # 维护操作（VACUUM、索引创建）
```

#### 1.1.3 存储配置

**推荐配置：**

- **Datanode 数据目录**：使用 SSD，IOPS > 10000
- **WAL 日志**：单独磁盘或分区，减少写入竞争
- **备份存储**：使用 HDD 或 NAS，成本低

**存储布局：**

```
/data/
├── opentenbase/
│   ├── datanode1/
│   │   ├── data/          # SSD：数据文件
│   │   └── pg_wal/        # SSD：WAL 日志
│   ├── datanode2/
│   └── datanode3/
└── backup/                # HDD：备份文件
```

### 1.2 网络规划

#### 1.2.1 网络拓扑

```
应用层
   ↓
[应用服务器]
   ↓ 1Gbps
[Coordinator 负载均衡]
   ↓ 10Gbps
┌─────────────────────────────────────┐
│  Coordinator 集群                   │
│  ├── CN1 (192.168.1.11)            │
│  ├── CN2 (192.168.1.12)            │
│  └── CN3 (192.168.1.13)            │
└─────────────────────────────────────┘
   ↓ 10Gbps
┌─────────────────────────────────────┐
│  GTM & Datanode 网络               │
│  ├── GTM (192.168.2.10)            │
│  ├── DN1 (192.168.2.21)            │
│  ├── DN2 (192.168.2.22)            │
│  ├── DN3 (192.168.2.23)            │
│  └── DN4 (192.168.2.24)            │
└─────────────────────────────────────┘
```

#### 1.2.2 网络优化

```ini
# 调整 TCP 参数
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr
```

---

## 2. 集群部署

### 2.1 部署规划

#### 2.1.1 节点数量建议

| 场景 | GTM | Coordinator | Datanode |
|------|-----|-------------|----------|
| 开发/测试 | 1 | 1 | 2 |
| 小型生产 | 1+1（Standby） | 2 | 4（2主2从） |
| 中型生产 | 1+1+1（Proxy） | 3 | 6（3主3从） |
| 大型生产 | 1+1+2（Proxy） | 4-8 | 8+（4+主从） |

#### 2.1.2 部署检查清单

- [ ] 检查操作系统版本（CentOS Stream 9 / Ubuntu 24.04）
- [ ] 检查 CPU、内存、磁盘满足要求
- [ ] 检查网络连通性
- [ ] 检查防火墙规则
- [ ] 配置 SSH 免密登录（可选）
- [ ] 检查系统时间同步（NTP）
- [ ] 安装依赖包
- [ ] 准备配置文件

### 2.2 配置优化

#### 2.2.1 GTM 配置

```ini
# gtm.conf
listen_addresses = '*'
port = 6666
nodename = 'gtm_master'
data_directory = '/opt/opentenbase/gtm/data'
startup = TXN
thread_count = 4  # 不要超过 CPU 核心数（注意：gtm_thread_count 不是合法参数）

# 高可用配置
gtm_standby_host = '192.168.2.11'
gtm_standby_port = 6666

# 日志配置
log_connections = on
log_disconnections = on
```

#### 2.2.2 Coordinator 配置

```ini
# postgresql.conf
max_connections = 200
shared_buffers = 4GB
effective_cache_size = 12GB
work_mem = 64MB
maintenance_work_mem = 256MB

# Coordinator 特有配置
coord_type = coordinator
enable_foreignkey = on
enable_hashjoin = on

# 性能优化
random_page_cost = 1.1  # SSD
effective_io_concurrency = 200  # SSD
```

#### 2.2.3 Datanode 配置

```ini
# postgresql.conf
max_connections = 100
shared_buffers = 8GB
effective_cache_size = 24GB
work_mem = 64MB
maintenance_work_mem = 512MB

# WAL 配置
wal_level = hot_standby
max_wal_senders = 5
wal_keep_size = 2GB
wal_compression = on

# 复制配置
synchronous_commit = remote_write  # 平衡性能和可靠性
synchronous_standby_names = 'dn2_standby'  # 同步复制节点

# 性能优化
random_page_cost = 1.1  # SSD
effective_io_concurrency = 200  # SSD
checkpoint_completion_target = 0.9
```

---

## 3. 表设计

### 3.1 分布策略选择

#### 3.1.1 HASH 分布

**适用场景：**
- 点查询频繁
- 分布列均匀分布
- 需要并行处理

```sql
-- 推荐：使用主键或唯一列
CREATE TABLE orders (
    order_id BIGINT PRIMARY KEY,
    user_id BIGINT,
    amount DECIMAL
) DISTRIBUTE BY HASH(order_id);

-- 推荐：使用高基数列（如用户 ID）
CREATE TABLE user_actions (
    action_id BIGINT,
    user_id BIGINT,
    action_time TIMESTAMP,
    action_type VARCHAR(50)
) DISTRIBUTE BY HASH(user_id);
```

**避免：**
- 使用低基数列（如性别、状态）
- 使用相关性弱的列

```sql
-- 不推荐：低基数列
CREATE TABLE logs (
    log_id BIGINT,
    log_level VARCHAR(10)  -- 只有 DEBUG/INFO/WARN/ERROR
    message TEXT
) DISTRIBUTE BY HASH(log_level);  -- 数据会倾斜

-- 修复：使用高基数列
CREATE TABLE logs (
    log_id BIGINT,
    log_level VARCHAR(10),
    message TEXT
) DISTRIBUTE BY HASH(log_id);
```

#### 3.1.2 MODULO 分布

**适用场景：**
- 分布列是连续整数
- 哈希分布成本高

```sql
CREATE TABLE events (
    event_id BIGINT,
    event_data JSONB
) DISTRIBUTE BY MODULO(event_id);
```

#### 3.1.3 REPLICATION 分布

**适用场景：**
- 小表（< 10000 行）
- 频繁连接的字典表
- 配置表

```sql
-- 字典表
CREATE TABLE regions (
    region_id INT PRIMARY KEY,
    region_name VARCHAR(50)
) DISTRIBUTE BY REPLICATION;

-- 配置表
CREATE TABLE system_config (
    config_key VARCHAR(50) PRIMARY KEY,
    config_value TEXT
) DISTRIBUTE BY REPLICATION;
```

### 3.2 主键和外键

#### 3.2.1 主键设计

```sql
-- 推荐：使用全局序列
CREATE GLOBAL SEQUENCE global_order_id START 1;

CREATE TABLE orders (
    order_id BIGINT PRIMARY KEY DEFAULT nextval('global_order_id'),
    user_id BIGINT,
    amount DECIMAL
) DISTRIBUTE BY HASH(order_id);
```

#### 3.2.2 外键设计

```sql
-- 父子表使用相同分布键，避免跨节点连接
CREATE TABLE orders (
    order_id BIGINT PRIMARY KEY,
    user_id BIGINT,
    order_date DATE,
    amount DECIMAL
) DISTRIBUTE BY HASH(order_id);

CREATE TABLE order_items (
    item_id BIGINT PRIMARY KEY,
    order_id BIGINT,
    product_id BIGINT,
    quantity INT,
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
) DISTRIBUTE BY HASH(order_id);  -- 相同分布键

-- 查询时避免跨节点连接
EXPLAIN SELECT * FROM orders o 
JOIN order_items oi ON o.order_id = oi.order_id;
-- 执行计划中不会有 REDISTRIBUTE Motion
```

### 3.3 索引设计

#### 3.3.1 选择合适的索引

```sql
-- 单列索引
CREATE INDEX idx_orders_user_id ON orders(user_id);

-- 复合索引（注意顺序）
CREATE INDEX idx_orders_user_date ON orders(user_id, order_date);
-- 适合查询：WHERE user_id = ? AND order_date > ?
-- 不适合查询：WHERE order_date > ?

-- 覆盖索引
CREATE INDEX idx_orders_user_amount ON orders(user_id) INCLUDE (amount);
-- 适合查询：SELECT user_id, amount FROM orders WHERE user_id = ?
```

#### 3.3.2 避免过度索引

```sql
-- 不推荐：每个列都建索引
CREATE INDEX idx_orders_amount ON orders(amount);
CREATE INDEX idx_orders_date ON orders(order_date);
CREATE INDEX idx_orders_status ON orders(status);
-- 索引过多会降低写入性能

-- 推荐：根据查询模式选择关键索引
CREATE INDEX idx_orders_user_date ON orders(user_id, order_date);
CREATE INDEX idx_orders_status_date ON orders(status, order_date);
```

#### 3.3.3 使用部分索引

```sql
-- 只为活跃订单创建索引
CREATE INDEX idx_orders_active ON orders(user_id, order_date)
WHERE status = 'active';
-- 节省存储空间，提升写入性能
```

### 3.4 数据类型选择

```sql
-- 推荐：使用合适的数据类型
CREATE TABLE users (
    user_id BIGINT,           -- 使用 BIGINT 而非 SERIAL
    username VARCHAR(100),    -- 限制长度而非 TEXT
    email VARCHAR(255),       -- 限制长度
    is_active BOOLEAN,        -- 使用 BOOLEAN
    created_at TIMESTAMP      -- 使用 TIMESTAMP
);

-- 不推荐：使用过大的数据类型
CREATE TABLE users (
    user_id TEXT,             -- 应该用 BIGINT
    username TEXT,            -- 应该用 VARCHAR
    data BYTEA                -- 避免，除非必要
);
```

---

## 4. SQL 优化

### 4.1 查询优化

#### 4.1.1 避免 SELECT *

```sql
-- 不推荐：获取所有列
SELECT * FROM orders WHERE user_id = 100;

-- 推荐：只查询需要的列
SELECT order_id, order_date, amount 
FROM orders 
WHERE user_id = 100;
```

#### 4.1.2 使用 WHERE 限制结果

```sql
-- 不推荐：查询大量数据
SELECT * FROM orders;

-- 推荐：使用 WHERE 条件
SELECT * FROM orders WHERE order_date > '2024-01-01';

-- 不推荐：在应用层分页
SELECT * FROM orders LIMIT 1000;
-- 然后在应用层跳过前 100 行

-- 推荐：使用 LIMIT OFFSET
SELECT * FROM orders LIMIT 100 OFFSET 100;
```

#### 4.1.3 避免 DISTINCT

```sql
-- 不推荐：使用 DISTINCT
SELECT DISTINCT user_id FROM orders;

-- 推荐：使用 GROUP BY
SELECT user_id FROM orders GROUP BY user_id;

-- 或使用 EXISTS
SELECT u.user_id FROM users u
WHERE EXISTS (
    SELECT 1 FROM orders o WHERE o.user_id = u.user_id
);
```

### 4.2 JOIN 优化

#### 4.2.1 选择合适的连接类型

```sql
-- 小表连接大表
SELECT * FROM small_table s
JOIN large_table l ON s.id = l.id;
-- 优化器会自动选择 Nested Loop

-- 大表连接大表
SELECT * FROM table1 t1
JOIN table2 t2 ON t1.id = t2.id;
-- 优化器会自动选择 Hash Join
```

#### 4.2.2 避免跨节点 JOIN

```sql
-- 确保连接表使用相同分布键
CREATE TABLE orders (
    order_id BIGINT PRIMARY KEY,
    user_id BIGINT,
    amount DECIMAL
) DISTRIBUTE BY HASH(order_id);

CREATE TABLE order_items (
    item_id BIGINT PRIMARY KEY,
    order_id BIGINT,
    product_id BIGINT,
    quantity INT
) DISTRIBUTE BY HASH(order_id);  -- 相同分布键

-- 查询时避免重分布
EXPLAIN SELECT * FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id;
```

#### 4.2.3 使用 CTE 优化复杂查询

```sql
-- 不推荐：嵌套子查询
SELECT * FROM (
    SELECT user_id, COUNT(*) AS cnt FROM orders GROUP BY user_id
) t WHERE cnt > 10;

-- 推荐：使用 CTE
WITH user_order_counts AS (
    SELECT user_id, COUNT(*) AS cnt
    FROM orders
    GROUP BY user_id
)
SELECT * FROM user_order_counts WHERE cnt > 10;
```

### 4.3 批量操作

#### 4.3.1 批量插入

```sql
-- 不推荐：逐条插入
INSERT INTO orders VALUES (1, 100, 100.00);
INSERT INTO orders VALUES (2, 101, 200.00);
INSERT INTO orders VALUES (3, 102, 300.00);

-- 推荐：批量插入
INSERT INTO orders VALUES
    (1, 100, 100.00),
    (2, 101, 200.00),
    (3, 102, 300.00);

-- 使用 COPY 批量导入
COPY orders FROM '/data/orders.csv' CSV HEADER;
```

#### 4.3.2 批量更新

```sql
-- 不推荐：逐条更新
UPDATE orders SET status = 'completed' WHERE order_id = 1;
UPDATE orders SET status = 'completed' WHERE order_id = 2;

-- 推荐：批量更新
UPDATE orders SET status = 'completed'
WHERE order_id IN (1, 2, 3, 4, 5);
```

#### 4.3.3 使用事务

```sql
-- 推荐：将多个操作放在一个事务中
BEGIN;
INSERT INTO orders VALUES (1, 100, 100.00);
INSERT INTO order_items VALUES (1, 1, 2001, 2);
UPDATE inventory SET quantity = quantity - 2 WHERE product_id = 2001;
COMMIT;
```

---

## 5. 性能优化

### 5.1 定期维护

#### 5.1.1 定期 ANALYZE

```sql
-- 每天执行 ANALYZE
ANALYZE;

-- 或使用自动清理
ALTER SYSTEM SET autovacuum = on;
ALTER SYSTEM SET autovacuum_naptime = '1min';
```

#### 5.1.2 定期 VACUUM

```sql
-- 定期执行 VACUUM
VACUUM orders;

-- 或配置自动清理
ALTER SYSTEM SET autovacuum_analyze_scale_factor = 0.1;
ALTER SYSTEM SET autovacuum_vacuum_scale_factor = 0.2;
```

#### 5.1.3 重建索引

```sql
-- 定期重建碎片化索引
REINDEX TABLE orders;

-- 或使用 CONCURRENTLY 避免锁表
REINDEX INDEX CONCURRENTLY idx_orders_user_id;
```

### 5.2 监控和调优

#### 5.2.1 监控慢查询

```sql
-- 启用慢查询日志
ALTER SYSTEM SET log_min_duration_statement = 1000;  -- 1秒

-- 查看慢查询
SELECT 
    query,
    calls,
    total_time,
    mean_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;
```

#### 5.2.2 监控锁等待

```sql
-- 查看锁等待
SELECT 
    pid,
    usename,
    query,
    wait_event_type,
    wait_event
FROM pg_stat_activity
WHERE wait_event IS NOT NULL;
```

#### 5.2.3 监控复制延迟

```sql
-- 在 Standby 节点查询
SELECT 
    pg_is_in_recovery(),
    pg_last_xact_replay_timestamp(),
    now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

### 5.3 参数调优

#### 5.3.1 工作内存调优

```sql
-- 根据查询复杂度调整
SET work_mem = '256MB';

-- 永久设置
ALTER SYSTEM SET work_mem = '256MB';
```

#### 5.3.2 连接数调优

```sql
-- 增加最大连接数
ALTER SYSTEM SET max_connections = 500;

-- 或使用连接池（推荐）
# 使用 pgBouncer 或其他连接池工具
```

#### 5.3.3 WAL 参数调优

```ini
# postgresql.conf
wal_buffers = 16MB
checkpoint_completion_target = 0.9
max_wal_size = 4GB
min_wal_size = 1GB
```

---

## 6. 高可用和备份

### 6.1 高可用架构

#### 6.1.1 GTM 高可用

```ini
# 配置 GTM Standby
# gtm_standby.conf
gtm_standby_host = '192.168.2.10'
gtm_standby_port = 6666
nodename = 'gtm_standby'
data_directory = '/opt/opentenbase/gtm_standby/data'
```

#### 6.1.2 Datanode 高可用

```sql
-- 配置流复制
-- postgresql.conf
wal_level = hot_standby
max_wal_senders = 5
wal_keep_size = 2GB
hot_standby = on

-- pg_hba.conf
host    replication     repuser         0.0.0.0/0               md5
```

#### 6.1.3 Coordinator 高可用

- 使用多个 Coordinator
- 通过负载均衡器（HAProxy、Nginx）分发请求
- 应用端实现故障切换

### 6.2 备份策略

#### 6.2.1 全量备份

```bash
# 每天全量备份
pg_dump -h localhost -p 15432 -U opentenbase \
    -F c -f /backup/opentenbase_$(date +%Y%m%d).dump opentenbase

# 保留 7 天
find /backup -name "opentenbase_*.dump" -mtime +7 -delete
```

#### 6.2.2 增量备份

```bash
# 使用 pg_basebackup 做基础备份
pg_basebackup -h localhost -p 15432 -U opentenbase \
    -D /backup/base -F t -z -P -X stream

# 备份 WAL 日志
cp /opt/opentenbase/datanode1/data/pg_wal/*.log /backup/wal/
```

#### 6.2.3 跨机房备份

```bash
# 使用 rsync 同步到远程机房
rsync -avz --delete /backup/ backup-server:/remote-backup/

# 或使用云存储
aws s3 sync /backup/ s3://opentenbase-backup/
```

### 6.3 恢复测试

```bash
# 定期测试恢复
# 1. 恢复备份到测试环境
pg_restore -h test-server -p 15432 -U opentenbase \
    -d opentenbase /backup/opentenbase_20240522.dump

# 2. 验证数据完整性
psql -h test-server -p 15432 -U opentenbase -d opentenbase \
    -c "SELECT COUNT(*) FROM orders;"

# 3. 执行关键查询验证功能
```

---

## 7. 安全最佳实践

### 7.1 访问控制

```sql
-- 创建不同权限的用户
CREATE USER app_user WITH PASSWORD 'strong_password';
CREATE USER readonly_user WITH PASSWORD 'strong_password';
CREATE USER admin_user WITH PASSWORD 'strong_password' SUPERUSER;

-- 授予权限
GRANT SELECT, INSERT, UPDATE ON orders TO app_user;
GRANT SELECT ON orders TO readonly_user;

-- 撤销不必要的权限
REVOKE ALL ON orders FROM public;
```

### 7.2 网络安全

```ini
# pg_hba.conf
# 只允许特定 IP 访问
host    opentenbase    app_user      192.168.1.0/24          md5
host    opentenbase    readonly_user 192.168.1.0/24          md5

# 拒绝其他连接
host    all            all           0.0.0.0/0               reject
```

### 7.3 SSL 加密

```ini
# postgresql.conf
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
ssl_ca_file = 'ca.crt'

# pg_hba.conf
hostssl opentenbase  app_user      0.0.0.0/0               md5
```

### 7.4 审计日志

```ini
# postgresql.conf
log_statement = 'all'  # 记录所有 SQL
log_duration = on
log_connections = on
log_disconnections = on
```

---

## 8. 运维建议

### 8.1 监控指标

#### 8.1.1 关键指标

- **集群健康**：所有节点状态
- **连接数**：当前连接数 vs 最大连接数
- **QPS**：每秒查询数
- **延迟**：查询平均响应时间
- **复制延迟**：Standby 与 Primary 的延迟
- **磁盘使用率**：数据目录和 WAL 目录
- **CPU 使用率**：各节点的 CPU 使用情况
- **内存使用率**：各节点的内存使用情况

#### 8.1.2 告警规则

```yaml
# 告警示例
alerts:
  - name: HighCPUUsage
    condition: cpu_usage > 80%
    duration: 5m
    severity: warning
    
  - name: DiskSpaceLow
    condition: disk_usage > 90%
    duration: 5m
    severity: critical
    
  - name: ReplicationLagHigh
    condition: replication_lag > 60s
    duration: 5m
    severity: warning
```

### 8.2 定期检查

#### 8.2.1 每日检查

```bash
# 检查节点状态
opentenbase-ctl status all

# 检查磁盘空间
df -h

# 检查错误日志
grep -i "error" /opt/opentenbase/*/log/*.log | tail -20
```

#### 8.2.2 每周检查

```bash
# 检查数据库大小
psql -c "SELECT pg_database_size('opentenbase');"

# 检查表大小
psql -c "SELECT pg_size_pretty(pg_total_relation_size('orders'));"

# 检查索引使用情况
psql -c "SELECT * FROM pg_stat_user_indexes WHERE idx_scan = 0;"
```

#### 8.2.3 每月检查

```bash
# 执行完整备份
pg_dump -f /backup/monthly/opentenbase_$(date +%Y%m).dump opentenbase

# 检查统计信息
psql -c "ANALYZE;"

# 检查数据倾斜
psql -c "SELECT node_name, count(*) FROM pgxc_node GROUP BY node_name;"
```

### 8.3 容量规划

#### 8.3.1 预测增长

```sql
-- 查看数据增长趋势
SELECT 
    date_trunc('month', order_date) AS month,
    COUNT(*) AS order_count,
    SUM(amount) AS total_amount
FROM orders
GROUP BY month
ORDER BY month DESC
LIMIT 12;
```

#### 8.3.2 扩展计划

- 当磁盘使用率达到 70% 时，开始规划扩容
- 当 QPS 接近单节点极限时，考虑增加 Coordinator
- 当数据量增长影响性能时，考虑增加 Datanode

---

## 9. 开发最佳实践

### 9.1 连接管理

```python
# 不推荐：频繁创建和销毁连接
for order in orders:
    conn = psycopg2.connect(...)
    cursor = conn.cursor()
    cursor.execute("INSERT INTO orders ...")
    conn.close()

# 推荐：使用连接池
from psycopg2 import pool

connection_pool = psycopg2.pool.SimpleConnectionPool(
    minconn=1,
    maxconn=10,
    host='localhost',
    port=15432,
    database='opentenbase',
    user='app_user',
    password='password'
)

def execute_query(sql, params=None):
    conn = connection_pool.getconn()
    try:
        cursor = conn.cursor()
        cursor.execute(sql, params)
        result = cursor.fetchall()
        conn.commit()
        return result
    finally:
        connection_pool.putconn(conn)
```

### 9.2 错误处理

```python
# 推荐：捕获并处理异常
try:
    conn = psycopg2.connect(...)
    cursor = conn.cursor()
    cursor.execute("INSERT INTO orders ...")
    conn.commit()
except psycopg2.IntegrityError as e:
    # 处理唯一约束冲突
    conn.rollback()
    logger.error(f"Duplicate order: {e}")
except psycopg2.OperationalError as e:
    # 处理连接错误
    logger.error(f"Connection error: {e}")
except Exception as e:
    # 处理其他错误
    conn.rollback()
    logger.error(f"Unexpected error: {e}")
finally:
    conn.close()
```

### 9.3 重试机制

```python
# 推荐：实现重试机制
from retrying import retry

@retry(stop_max_attempt_number=3, wait_exponential_multiplier=1000, wait_exponential_max=10000)
def execute_with_retry(sql, params=None):
    conn = psycopg2.connect(...)
    try:
        cursor = conn.cursor()
        cursor.execute(sql, params)
        conn.commit()
        return cursor.fetchall()
    except psycopg2.OperationalError as e:
        logger.warning(f"Query failed, retrying: {e}")
        raise
    finally:
        conn.close()
```

---

## 10. 常见陷阱

### 10.1 分布列选择错误

```sql
-- 陷阱：使用低基数列导致数据倾斜
CREATE TABLE orders (
    order_id BIGINT,
    user_id BIGINT,
    status VARCHAR(20)  -- 只有几个值
) DISTRIBUTE BY HASH(status);

-- 结果：大部分数据集中在一个节点
```

### 10.2 跨节点事务过多

```sql
-- 陷阱：频繁的跨节点事务
BEGIN;
UPDATE orders SET status = 'completed' WHERE order_id = 1;  -- DN1
UPDATE inventory SET quantity = quantity - 1 WHERE product_id = 100;  -- DN2
COMMIT;

-- 结果：性能下降，GTM 压力增大
```

### 10.3 忽略统计信息

```sql
-- 陷阱：大数据量导入后不收集统计信息
COPY orders FROM '/data/large_orders.csv' CSV;
-- 直接查询，性能差

-- 正确做法：
COPY orders FROM '/data/large_orders.csv' CSV;
ANALYZE orders;  -- 收集统计信息
-- 再查询，性能提升
```

### 10.4 过度使用全局索引

```sql
-- 陷阱：为每个唯一列创建全局索引
CREATE UNIQUE INDEX GLOBAL idx_orders_order_id ON orders(order_id);
CREATE UNIQUE INDEX GLOBAL idx_orders_user_id ON orders(user_id);
CREATE UNIQUE INDEX GLOBAL idx_orders_date ON orders(order_date);

-- 结果：写入性能严重下降
```

---

## 11. 总结

OpenTenBase 最佳实践的核心原则：

1. **架构优先**：合理的架构是性能的基础
2. **数据分布**：选择合适的分布策略避免数据倾斜
3. **查询优化**：编写高效的 SQL，避免跨节点操作
4. **定期维护**：定期 ANALYZE、VACUUM，保持数据库健康
5. **监控告警**：及时发现和解决问题
6. **备份恢复**：定期备份，定期测试恢复
7. **安全第一**：最小权限原则，网络隔离，加密传输
8. **持续优化**：根据实际使用情况持续调整和优化

遵循这些最佳实践，可以构建高性能、高可用、安全的 OpenTenBase 集群。

---

## 12. 延伸阅读

- [03-architecture.md](./03-architecture.md)：架构详解
- [04-advanced.md](./04-advanced.md)：高级功能
- [05-troubleshoot.md](./05-troubleshoot.md)：故障排查

---

**作者：** OpenTenBase 社区  
**更新时间：** 2024-05  
**版本：** 1.0