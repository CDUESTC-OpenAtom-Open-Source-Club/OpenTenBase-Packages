# OpenTenBase 测试清单

## 1. Docker 部署测试

### 1.1 基础设施测试

| 测试项 | 命令 | 预期结果 | 状态 |
|--------|------|----------|------|
| Docker 服务运行 | `docker info` | 显示 Docker 信息 | ☐ |
| Docker 网络创建 | `docker network ls` | 存在 opentenbase 网络 | ☐ |
| Docker 卷创建 | `docker volume ls` | 存在 4 个数据卷 | ☐ |

### 1.2 镜像构建测试

| 测试项 | 命令 | 预期结果 | 状态 |
|--------|------|----------|------|
| 基础镜像存在 | `docker images euleros-base` | 显示镜像 | ☐ |
| 运行时镜像构建 | `docker-compose build` | 构建成功 | ☐ |
| 镜像大小合理 | `docker images opentenbase-runtime` | < 4GB | ☐ |

### 1.3 容器启动测试

| 测试项 | 命令 | 预期结果 | 状态 |
|--------|------|----------|------|
| GTM 容器启动 | `docker ps \| grep gtm` | Up 状态 | ☐ |
| Coordinator 启动 | `docker ps \| grep coordinator` | Up 状态 | ☐ |
| Datanode1 启动 | `docker ps \| grep datanode1` | Up 状态 | ☐ |
| Datanode2 启动 | `docker ps \| grep datanode2` | Up 状态 | ☐ |

### 1.4 端口映射测试

| 测试项 | 命令 | 预期结果 | 状态 |
|--------|------|----------|------|
| GTM 端口 6666 | `nc -z localhost 6666` | 连接成功 | ☐ |
| Coordinator 端口 5432 | `nc -z localhost 5432` | 连接成功 | ☐ |
| Datanode1 端口 15432 | `nc -z localhost 15432` | 连接成功 | ☐ |
| Datanode2 端口 15433 | `nc -z localhost 15433` | 连接成功 | ☐ |

### 1.5 日志检查

| 测试项 | 命令 | 预期结果 | 状态 |
|--------|------|----------|------|
| GTM 无错误 | `docker logs opentenbase-gtm 2>&1 \| grep -i error` | 无输出 | ☐ |
| Coordinator 无错误 | `docker logs opentenbase-coordinator 2>&1 \| grep -i error` | 无输出 | ☐ |
| Datanode1 无错误 | `docker logs opentenbase-datanode1 2>&1 \| grep -i error` | 无输出 | ☐ |
| Datanode2 无错误 | `docker logs opentenbase-datanode2 2>&1 \| grep -i error` | 无输出 | ☐ |

## 2. 集群配置测试

### 2.1 节点注册测试

```bash
docker exec opentenbase-coordinator psql -h 127.0.0.1 -U opentenbase -d postgres -c "SELECT node_name, node_type, node_host, node_port FROM pgxc_node ORDER BY node_name;"
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| gtm_master 节点存在 | node_type='G' | ☐ |
| coordinator 节点存在 | node_type='C' | ☐ |
| datanode1 节点存在 | node_type='D' | ☐ |
| datanode2 节点存在 | node_type='D' | ☐ |

### 2.2 节点组测试

```bash
docker exec opentenbase-coordinator psql -h 127.0.0.1 -U opentenbase -d postgres -c "SELECT * FROM pgxc_group;"
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| default_group 存在 | 显示组信息 | ☐ |
| 包含 2 个 datanode | datanode1, datanode2 | ☐ |

### 2.3 分片测试

```bash
docker exec opentenbase-coordinator psql -h 127.0.0.1 -U opentenbase -d postgres -c "SELECT * FROM pgxc_shard_map;"
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| 分片映射存在 | 显示分片信息 | ☐ |
| 分片均匀分布 | 两个 datanode 各有分片 | ☐ |

## 3. CRUD 功能测试

### 3.1 表创建测试

```sql
-- 连接 Coordinator
docker exec -it opentenbase-coordinator psql -h 127.0.0.1 -U opentenbase -d postgres

-- 创建分布式表
CREATE TABLE test_sharding (
    id serial PRIMARY KEY,
    name varchar(50),
    created_at timestamp DEFAULT now()
) DISTRIBUTE BY SHARDING (id) TO GROUP default_group;

-- 验证表创建
\dt
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| 表创建成功 | 无错误 | ☐ |
| 表在 pg_tables 中可见 | 显示 test_sharding | ☐ |

### 3.2 数据插入测试

```sql
-- 批量插入
INSERT INTO test_sharding (name)
SELECT 'user_' || generate_series(1, 1000);

-- 验证插入
SELECT count(*) FROM test_sharding;
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| 插入成功 | 无错误 | ☐ |
| 记录数正确 | 1000 | ☐ |

### 3.3 数据查询测试

```sql
-- 基本查询
SELECT * FROM test_sharding LIMIT 10;

-- 聚合查询
SELECT name, count(*) FROM test_sharding GROUP BY name LIMIT 5;

-- 跨节点查询
SELECT * FROM test_sharding WHERE id > 500 AND id < 600;
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| 基本查询成功 | 返回数据 | ☐ |
| 聚合查询成功 | 返回统计 | ☐ |
| 跨节点查询成功 | 返回数据 | ☐ |

### 3.4 数据更新测试

```sql
-- 更新数据
UPDATE test_sharding SET name = 'updated' WHERE id = 1;

-- 验证更新
SELECT * FROM test_sharding WHERE id = 1;
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| 更新成功 | 无错误 | ☐ |
| 数据已更新 | name='updated' | ☐ |

### 3.5 数据删除测试

```sql
-- 删除数据
DELETE FROM test_sharding WHERE id = 1;

-- 验证删除
SELECT * FROM test_sharding WHERE id = 1;
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| 删除成功 | 无错误 | ☐ |
| 数据已删除 | 0 行 | ☐ |

### 3.6 表删除测试

```sql
-- 删除表
DROP TABLE test_sharding;

-- 验证删除
\dt test_sharding
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| 表删除成功 | 无错误 | ☐ |
| 表不存在 | "Did not find any relation" | ☐ |

## 4. 高级功能测试

### 4.1 事务测试

```sql
-- 事务提交
BEGIN;
INSERT INTO test_sharding (name) VALUES ('tx_test');
COMMIT;
SELECT * FROM test_sharding WHERE name = 'tx_test';

-- 事务回滚
BEGIN;
INSERT INTO test_sharding (name) VALUES ('rollback_test');
ROLLBACK;
SELECT * FROM test_sharding WHERE name = 'rollback_test';
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| 事务提交成功 | 数据可见 | ☐ |
| 事务回滚成功 | 数据不可见 | ☐ |

### 4.2 连接池测试

```bash
# 并发连接测试
for i in {1..10}; do
    docker exec opentenbase-coordinator psql -h 127.0.0.1 -U opentenbase -d postgres -c "SELECT 1;" &
done
wait
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| 10 并发连接成功 | 全部返回 1 | ☐ |
| 无连接错误 | 无错误输出 | ☐ |

### 4.3 数据类型测试

```sql
CREATE TABLE test_types (
    id serial PRIMARY KEY,
    val_int integer,
    val_text text,
    val_json jsonb,
    val_ts timestamp,
    val_array integer[]
) DISTRIBUTE BY SHARDING (id) TO GROUP default_group;

INSERT INTO test_types (val_int, val_text, val_json, val_ts, val_array)
VALUES (42, 'hello', '{"key": "value"}', now(), ARRAY[1,2,3]);

SELECT * FROM test_types;
DROP TABLE test_types;
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| 各类型插入成功 | 无错误 | ☐ |
| 数据读取正确 | 值匹配 | ☐ |

## 5. 性能基准测试

### 5.1 批量插入性能

```sql
CREATE TABLE bench_insert (id serial, data text)
DISTRIBUTE BY SHARDING (id) TO GROUP default_group;

\timing on
INSERT INTO bench_insert (data)
SELECT 'data_' || generate_series(1, 100000);
\timing off

SELECT count(*) FROM bench_insert;
DROP TABLE bench_insert;
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| 10万行插入 < 30秒 | 通过 | ☐ |
| 记录数正确 | 100000 | ☐ |

### 5.2 查询性能

```sql
CREATE TABLE bench_query (id serial, data text)
DISTRIBUTE BY SHARDING (id) TO GROUP default_group;

INSERT INTO bench_query (data)
SELECT 'data_' || generate_series(1, 100000);

\timing on
SELECT count(*) FROM bench_query;
SELECT * FROM bench_query WHERE id = 50000;
\timing off

DROP TABLE bench_query;
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| 全表计数 < 5秒 | 通过 | ☐ |
| 点查 < 1秒 | 通过 | ☐ |

## 6. 故障恢复测试

### 6.1 容器重启测试

```bash
# 重启 GTM
docker restart opentenbase-gtm
sleep 10

# 验证集群仍可用
docker exec opentenbase-coordinator psql -h 127.0.0.1 -U opentenbase -d postgres -c "SELECT 1;"
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| GTM 重启成功 | 容器 Up | ☐ |
| 集群仍可用 | 返回 1 | ☐ |

### 6.2 Datanode 重启测试

```bash
# 重启 Datanode1
docker restart opentenbase-datanode1
sleep 10

# 验证数据完整性
docker exec opentenbase-coordinator psql -h 127.0.0.1 -U opentenbase -d postgres -c "SELECT count(*) FROM test_sharding;"
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| Datanode1 重启成功 | 容器 Up | ☐ |
| 数据完整 | 计数正确 | ☐ |

## 7. 清理测试

```bash
# 停止并删除所有容器
docker-compose down -v

# 验证清理
docker ps -a
docker volume ls
```

| 测试项 | 预期结果 | 状态 |
|--------|----------|------|
| 容器全部删除 | 无容器 | ☐ |
| 卷全部删除 | 无数据卷 | ☐ |

---

## 测试执行记录

| 日期 | 测试人 | 通过/总数 | 备注 |
|------|--------|-----------|------|
| | | / | |

## 已知问题

1. **Docker 18.09 不支持 `docker compose`**
   - 解决方案：使用 `docker-compose`（Python 版本）

2. **hdspace 隧道不稳定**
   - 解决方案：在服务器上直接执行命令

3. **/tmp 空间不足**
   - 解决方案：使用 home 目录传输文件
