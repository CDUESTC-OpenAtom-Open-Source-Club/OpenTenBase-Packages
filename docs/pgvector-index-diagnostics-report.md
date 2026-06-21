# pgvector 向量索引构建与诊断能力增强技术报告

## 1. 项目方向

本阶段选择“项目二：向量索引构建与诊断能力增强”作为独立交付方向，目标是让 OpenTenBase/TDSQL-A 用户更容易发现以下问题：

- IVFFlat 索引构建慢或失败。
- `maintenance_work_mem` 不足导致索引构建失败。
- `lists/probes` 设置不合理导致召回率低或延迟过高。
- 查询写法不满足 IVFFlat 计划条件，导致退化为 Seq Scan。
- 数据规模、维度、目标召回变化后缺少可执行参数建议。

项目一已经完成可复现 benchmark 和 100000 行、128 维、L2/IP/Cosine 的 recall/latency 基线。项目二在此基础上把“测试数据”进一步沉淀为“诊断工具”和“调优流程”。

## 2. 交付物

本阶段新增：

```text
patches/pgvector-ivfflat-diagnostics-tools.patch
scripts/pgvector-index-diagnostics.sh
docs/pgvector-index-diagnostics-report.md
docs/pgvector-production-tuning-template.md
docs/pgvector-ai-reproducible-sop.md
```

源码补丁新增：

```text
contrib/pgvector/bench/ivfflat_diagnostics.sql
```

诊断 SQL 提供：

- `pgvector_bench.parse_memory_mb(text)`
- `pgvector_bench.estimate_ivfflat_build_memory_mb(row_count, dims, lists)`
- `pgvector_bench.recommend_ivfflat_lists(row_count, dims)`
- `pgvector_bench.diagnose_ivfflat_build(row_count, dims, lists, probes, target_recall, maintenance_work_mem)`
- `pgvector_bench.ivfflat_index_inventory`

## 3. 诊断设计

### 3.1 构建内存风险

IVFFlat 构建需要较大的工作内存。项目一实测中，`ROWS=100000`、`DIMS=128`、`LISTS=1000` 在默认 `maintenance_work_mem=64MB` 下出现过索引构建失败。

诊断函数会估算构建内存，并和当前或指定的 `maintenance_work_mem` 对比：

```sql
SELECT *
FROM pgvector_bench.diagnose_ivfflat_build(
  row_count => 100000,
  dims => 128,
  lists => 1000,
  probes => 10,
  target_recall => 0.90,
  maintenance_work_mem => '64MB'
);
```

预期风险：

```text
maintenance_work_mem = risk
recommendation = increase maintenance_work_mem ... or reduce lists/rows per build
```

### 3.2 lists/probes 风险

诊断函数不会把某一组参数写成普适答案，而是返回风险等级和建议：

- `probes/lists` 过低：提示召回率风险。
- `probes = lists`：提示召回率通常较高，但延迟可能接近或超过 exact scan。
- 未显式传入 `lists/probes`：按数据规模、维度和目标召回给出启发式起点。

### 3.3 索引清单

`ivfflat_index_inventory` 视图用于发现当前数据库中已有的 IVFFlat 索引：

```sql
SELECT schema_name, table_name, index_name, pg_size_pretty(index_bytes), index_definition
FROM pgvector_bench.ivfflat_index_inventory;
```

该视图可用于报告已有索引数量、索引大小和索引定义，帮助判断是否存在重复索引、错误 opclass 或非预期表。

## 4. 使用方式

加载诊断 SQL：

```bash
psql -d postgres -f contrib/pgvector/bench/ivfflat_diagnostics.sql
```

使用安装包仓库脚本运行诊断：

```bash
PGHOST=127.0.0.1 PGPORT=5432 PGUSER=opentenbase DBNAME=postgres \
ROW_COUNT=100000 DIMS=128 LISTS=1000 PROBES=10 \
TARGET_RECALL=0.90 MAINTENANCE_WORK_MEM=64MB \
SQL_FILE=/workspace/OpenTenBase/contrib/pgvector/bench/ivfflat_diagnostics.sql \
scripts/pgvector-index-diagnostics.sh
```

高召回配置诊断：

```bash
PGHOST=127.0.0.1 PGPORT=5432 PGUSER=opentenbase DBNAME=postgres \
ROW_COUNT=100000 DIMS=128 LISTS=1000 PROBES=500 \
TARGET_RECALL=0.90 MAINTENANCE_WORK_MEM=512MB \
scripts/pgvector-index-diagnostics.sh
```

## 5. 异常场景覆盖

| 场景 | 诊断能力 | 建议 |
| --- | --- | --- |
| `maintenance_work_mem` 过低 | `maintenance_work_mem = risk` | 提高内存或降低 lists/分批构建 |
| 低 probes 高 recall 目标 | `probes = risk/warn` | benchmark `lists*0.3`、`lists*0.5`、`lists` |
| probes 等于 lists | `probes = warn` | 对比 exact scan，避免延迟超过收益 |
| 未设置 lists | 返回推荐 lists | 以推荐值为起点，再跑 benchmark |
| 查询未命中索引 | 项目一 benchmark plan 输出识别 | 确认 `ORDER BY` 只包含距离表达式 |

## 6. 与项目一的关系

项目一解决“如何测”和“测出了什么”；项目二解决“用户看到问题后如何定位和调参”。

项目一产物：

- benchmark 工具。
- recall/latency 数据。
- plan 证据。
- 参数推荐初版。

项目二新增：

- 构建内存估算。
- lists/probes 风险分级。
- IVFFlat 索引清单。
- 可复用诊断脚本。
- 生产调优模板。

## 7. 验证状态

本地已完成函数级验证，结果文件：

```text
docs/diagnostic-results/pgvector-diagnostics-local-validation.txt
```

验证环境：

```text
PostgreSQL 14.22 (Homebrew) on aarch64-apple-darwin24.6.0
```

已验证：

- `scripts/pgvector-index-diagnostics.sh` shell 语法检查。
- `patches/pgvector-ivfflat-diagnostics-tools.patch` 生成检查。
- SOP、报告、调优模板路径检查。
- `parse_memory_mb('512MB') = 512`。
- `recommend_ivfflat_lists(100000, 128) = 1000`。
- `estimate_ivfflat_build_memory_mb(100000,128,1000) = 246`，能够覆盖项目一中 64MB 构建失败的风险。
- `diagnose_ivfflat_build(100000,128,1000,10,0.90,'64MB')` 返回 `maintenance_work_mem = risk` 和 `probes = risk`。
- `diagnose_ivfflat_build(100000,128,1000,500,0.90,'512MB')` 返回 `maintenance_work_mem = ok` 和 `probes = ok`。
- `scripts/pgvector-index-diagnostics.sh` 已串联加载 SQL、执行诊断和查询索引清单。

远程 OpenTenBase 验证状态：

- 远程 CloudStudio SSH 当前直接断开，暂时无法补充分布式 OpenTenBase 实测输出。
- 由于诊断 SQL 主要为标准 SQL/PLpgSQL 逻辑，本地 PostgreSQL 已覆盖语法和主要函数行为。
- `ivfflat_index_inventory` 的 OpenTenBase 实库索引清单仍需在远程恢复后补测。

远程恢复后的补测命令：

1. 加载 `ivfflat_diagnostics.sql`。
2. 验证低内存场景返回 `risk`。
3. 验证高 probes 场景返回 `warn/ok`。
4. 查询 `ivfflat_index_inventory`，确认能列出现有 IVFFlat 索引。

如果远程环境临时不可用，应保留 SQL、命令和预期输出，待环境恢复后补充实测结果，不应伪造验证数据。

## 8. 后续增强

1. 将项目一 benchmark CSV 自动导入观测表，形成更丰富的 measured recommendation。
2. 增加 clustered/skewed 数据集，验证非均匀分布下的低召回风险。
3. 增加索引构建耗时采样，输出构建耗时与 `maintenance_work_mem` 的关系。
4. 对接 OpenTenBase `pg_stat_cluster_activity`、`pg_stat_cluster_query_memory` 等视图，补充分布式资源观测。
5. 形成独立 PR：`pgvector IVFFlat diagnostics tools`。
