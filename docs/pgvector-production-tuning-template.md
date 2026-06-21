# OpenTenBase pgvector 生产调优模板

## 1. 基本信息

| 项目 | 填写 |
| --- | --- |
| 业务场景 | 例如 RAG、相似商品、日志向量检索 |
| 向量来源 | 例如 embedding model 名称和版本 |
| 数据规模 | rows = |
| 向量维度 | dims = |
| 距离类型 | L2 / Inner Product / Cosine |
| TopK | |
| 目标 recall | |
| 延迟预算 | avg / p95 / p99 |
| OpenTenBase 版本 | |
| 节点形态 | 单机 / 分布式 |

## 2. 建索引前检查

```sql
SELECT *
FROM pgvector_bench.diagnose_ivfflat_build(
  row_count => <rows>,
  dims => <dims>,
  lists => NULL,
  probes => NULL,
  target_recall => <target_recall>,
  maintenance_work_mem => current_setting('maintenance_work_mem')
);
```

检查项：

- `lists` 是否合理。
- `maintenance_work_mem` 是否低于估算值。
- 初始 `probes` 是否存在低召回风险。
- 是否需要先降低数据规模做 smoke benchmark。

## 3. 推荐配置起点

| rows | dims | 建议 lists 起点 | 建议 probes 起点 | maintenance_work_mem 起点 |
| ---: | ---: | ---: | ---: | --- |
| 10000-50000 | 64-128 | `sqrt(rows) * 2` 附近 | `lists * 0.1` 到 `lists * 0.5` | 128MB-256MB |
| 100000-300000 | 128-384 | `sqrt(rows) * 3.2` 附近 | `lists * 0.3` 到 `lists * 0.75` | 512MB-1GB |
| 1000000+ | 384+ | 分多档验证 | 按 recall 目标逐步提升 | 1GB+，按实际构建内存估算 |

注意：表格只作为起点，不是生产保证。正式上线必须使用业务数据复跑 recall/latency benchmark。

## 4. Benchmark 命令模板

```bash
cd contrib/pgvector

PGHOST=<host> PGPORT=<port> PGUSER=<user> DBNAME=<db> \
ROWS=<rows> DIMS=<dims> QUERIES=<queries> TOPK=<topk> \
LISTS=<lists> PROBES_LIST="1 5 10 50 100 <lists/2> <lists>" \
METRICS="l2 ip cosine" MAINTENANCE_WORK_MEM=<mem> \
bench/run_ivfflat_benchmark.sh
```

必须保存：

```text
bench/results/*.csv
bench/results/*_plans.txt
```

## 5. 查询写法检查

推荐写法：

```sql
SELECT id
FROM items
ORDER BY embedding <=> '[...]'
LIMIT 10;
```

高风险写法：

```sql
ORDER BY embedding <=> '[...]', id
```

原因：二级排序可能导致 IVFFlat 不能被选中，查询退化为 `Seq Scan + Sort`。

必须用 `EXPLAIN` 验证：

```text
Index Scan using ... ivfflat ...
```

## 6. 低召回处理

如果 recall 低：

1. 增大 `ivfflat.probes`。
2. 检查 `lists` 是否过大导致每个 list 数据太少。
3. 对 Cosine/IP 场景检查向量是否需要归一化。
4. 使用 clustered/skewed 数据集做负向测试。
5. 对比 exact scan，确认评估逻辑正确。

## 7. 构建失败处理

如果出现类似内存不足：

```text
memory required is ... maintenance_work_mem is ...
```

处理顺序：

1. 使用 `diagnose_ivfflat_build` 估算所需内存。
2. 临时提高 `maintenance_work_mem`。
3. 降低 `lists`。
4. 分批导入数据后重建索引。
5. 避免多个大 IVFFlat 索引并发构建。

## 8. 日志与磁盘

建议配置：

```text
logging_collector = on
log_rotation_size = '100MB'
log_truncate_on_rotation = on
```

检查命令：

```bash
df -h /
du -sh /var/log/opentenbase/* 2>/dev/null || true
```

## 9. 上线前验收

| 项目 | 通过标准 |
| --- | --- |
| extension | `CREATE EXTENSION vector` 成功 |
| index build | IVFFlat 索引构建成功，无内存错误 |
| plan | 查询走 IVFFlat Index Scan |
| recall | 满足业务目标 |
| latency | avg/p95/p99 满足预算 |
| logs | 日志轮转启用，磁盘无异常增长 |
| rollback | 可删除索引或切换 exact scan |

